defmodule CryptalearnNode.Nodes.Registry do
  @moduledoc """
  Registry for managing node sessions with supervision and health monitoring.

  This module provides a centralized registry for all client node sessions,
  handles registration/deregistration, and manages session lifecycle.
  """

  use GenServer
  require Logger

  alias CryptalearnNode.Nodes.{NodeSession, SessionManager}
  alias CryptalearnNode.Repo

  @cleanup_interval 60_000 # 1 minute
  @session_timeout 300_000 # 5 minutes

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new node session.
  """
  def register_node(node_id, params \\ %{}) do
    GenServer.call(__MODULE__, {:register_node, node_id, params})
  end

  @doc """
  Deregister a node session.
  """
  def deregister_node(node_id) do
    GenServer.call(__MODULE__, {:deregister_node, node_id})
  end

  @doc """
  Get the status of a specific node.
  """
  def get_node_status(node_id) do
    GenServer.call(__MODULE__, {:get_node_status, node_id})
  end

  @doc """
  List all active nodes.
  """
  def list_active_nodes do
    GenServer.call(__MODULE__, :list_active_nodes)
  end

  @doc """
  Record a heartbeat from a node.
  """
  def heartbeat(node_id) do
    GenServer.cast(__MODULE__, {:heartbeat, node_id})
  end

  @doc """
  Get nodes by capability.
  """
  def get_nodes_by_capability(capability) do
    GenServer.call(__MODULE__, {:get_nodes_by_capability, capability})
  end

  @doc """
  Update node training status.
  """
  def update_training_status(node_id, round_id, status) do
    GenServer.cast(__MODULE__, {:update_training_status, node_id, round_id, status})
  end

  # Server Callbacks

  def init(_opts) do
    # Schedule periodic cleanup
    schedule_cleanup()

    state = %{
      nodes: %{},
      capabilities_index: %{}
    }

    {:ok, state}
  end

  def handle_call({:register_node, node_id, params}, _from, state) do
    case do_register_node(node_id, params) do
      {:ok, session_data} ->
        # Update local state
        new_nodes = Map.put(state.nodes, node_id, session_data)
        new_capabilities = update_capabilities_index(
          state.capabilities_index,
          node_id,
          params[:capabilities] || []
        )

        new_state = %{state |
          nodes: new_nodes,
          capabilities_index: new_capabilities
        }

        Logger.info("Node registered: #{node_id} with capabilities: #{inspect(params[:capabilities])}")

        {:reply, {:ok, session_data}, new_state}

      {:error, reason} ->
        Logger.warning("Failed to register node #{node_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:deregister_node, node_id}, _from, state) do
    do_deregister_node(node_id)

    # Update local state
    {_removed, new_nodes} = Map.pop(state.nodes, node_id)
    new_capabilities = remove_from_capabilities_index(state.capabilities_index, node_id)

    new_state = %{state |
      nodes: new_nodes,
      capabilities_index: new_capabilities
    }

    Logger.info("Node deregistered: #{node_id}")
    {:reply, :ok, new_state}
  end

  def handle_call({:get_node_status, node_id}, _from, state) do
    case Map.get(state.nodes, node_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _node_data ->
        # Get fresh status from the session process
        case SessionManager.get_status(node_id) do
          {:ok, status} -> {:reply, {:ok, status}, state}
          error -> {:reply, error, state}
        end
    end
  end

  def handle_call(:list_active_nodes, _from, state) do
    active_nodes = state.nodes
    |> Enum.map(fn {node_id, _data} ->
      case SessionManager.get_status(node_id) do
        {:ok, status} -> {node_id, status}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{})

    {:reply, {:ok, active_nodes}, state}
  end

  def handle_call({:get_nodes_by_capability, capability}, _from, state) do
    nodes = Map.get(state.capabilities_index, capability, [])
    |> Enum.map(fn node_id ->
      case SessionManager.get_status(node_id) do
        {:ok, status} -> {node_id, status}
        _ -> nil
      end
    end)
    |> Enum.filter(&(&1 != nil))
    |> Enum.into(%{})

    {:reply, {:ok, nodes}, state}
  end

  def handle_cast({:heartbeat, node_id}, state) do
    if Map.has_key?(state.nodes, node_id) do
      SessionManager.heartbeat(node_id)

      # Update last seen in local state
              updated_nodes = Map.update!(state.nodes, node_id, fn node_data ->
          Map.put(node_data, :last_heartbeat, DateTime.utc_now() |> DateTime.truncate(:second))
        end)

      {:noreply, %{state | nodes: updated_nodes}}
    else
      Logger.warning("Received heartbeat from unregistered node: #{node_id}")
      {:noreply, state}
    end
  end

  def handle_cast({:update_training_status, node_id, round_id, status}, state) do
    if Map.has_key?(state.nodes, node_id) do
      SessionManager.update_training_status(node_id, round_id, status)

      # Update local state
      updated_nodes = Map.update!(state.nodes, node_id, fn node_data ->
        node_data
        |> Map.put(:status, status)
        |> Map.put(:current_round_id, round_id)
      end)

      {:noreply, %{state | nodes: updated_nodes}}
    else
      Logger.warning("Received training status update from unregistered node: #{node_id}")
      {:noreply, state}
    end
  end

  def handle_info(:cleanup_sessions, state) do
    cleanup_count = cleanup_inactive_sessions(state.nodes)

    if cleanup_count > 0 do
      Logger.info("Cleaned up #{cleanup_count} inactive sessions")
    end

    # Refresh state from database
    refreshed_state = refresh_state_from_db(state)

    # Schedule next cleanup
    schedule_cleanup()

    {:noreply, refreshed_state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # Handle session process termination
    case find_node_by_pid(state.nodes, pid) do
      {:ok, node_id} ->
        Logger.warning("Session process for node #{node_id} terminated: #{inspect(reason)}")

        # Remove from database and local state
        do_deregister_node(node_id)

        {_removed, new_nodes} = Map.pop(state.nodes, node_id)
        new_capabilities = remove_from_capabilities_index(state.capabilities_index, node_id)

        new_state = %{state |
          nodes: new_nodes,
          capabilities_index: new_capabilities
        }

        {:noreply, new_state}

      :not_found ->
        {:noreply, state}
    end
  end

  # Private helper functions

  defp do_register_node(node_id, params) do
    # Check if node already exists
    case Repo.get_by(NodeSession, node_id: node_id) do
      nil ->
        # Create new session
        create_new_session(node_id, params)

      existing_session ->
        # Update existing session
        update_existing_session(existing_session, params)
    end
  end

  defp create_new_session(node_id, params) do
    session_params = Map.merge(params, %{node_id: node_id})

    changeset = NodeSession.registration_changeset(%NodeSession{}, session_params)

    case Repo.insert(changeset) do
      {:ok, session} ->
        # Start session process
        case start_session_process(session) do
          {:ok, pid} ->
            {:ok, session_to_response(session, pid)}

          {:error, reason} ->
            # Clean up database entry
            Repo.delete(session)
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, extract_changeset_errors(changeset)}
    end
  end

  defp update_existing_session(session, params) do
    changeset = NodeSession.registration_changeset(session, params)

    case Repo.update(changeset) do
      {:ok, updated_session} ->
        # Restart session process with new data
        case restart_session_process(updated_session) do
          {:ok, pid} ->
            {:ok, session_to_response(updated_session, pid)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, changeset} ->
        {:error, extract_changeset_errors(changeset)}
    end
  end

  defp do_deregister_node(node_id) do
    # Stop session process
    case Registry.lookup(CryptalearnNode.NodeRegistry, node_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(CryptalearnNode.Nodes.SessionSupervisor, pid)

      [] ->
        :ok
    end

    # Remove from database
    case Repo.get_by(NodeSession, node_id: node_id) do
      nil -> :ok
      session ->
        case Repo.delete(session) do
          {:ok, _} -> :ok
          {:error, _} -> :ok  # Don't fail if deletion fails
        end
    end

    :ok
  end

  defp start_session_process(session) do
    session_spec = {
      SessionManager,
      [
        node_id: session.node_id,
        session_data: session
      ]
    }

    case DynamicSupervisor.start_child(CryptalearnNode.Nodes.SessionSupervisor, session_spec) do
      {:ok, pid} ->
        # Register the process in the registry
        Registry.register(CryptalearnNode.NodeRegistry, session.node_id, %{
          pid: pid,
          started_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        {:ok, pid}

      error ->
        error
    end
  end

  defp restart_session_process(session) do
    # Stop existing process
    case Registry.lookup(CryptalearnNode.NodeRegistry, session.node_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(CryptalearnNode.Nodes.SessionSupervisor, pid)

      [] ->
        :ok
    end

    # Start new process
    start_session_process(session)
  end

  defp update_capabilities_index(index, node_id, capabilities) do
    # Remove node from old capabilities
    cleaned_index = remove_from_capabilities_index(index, node_id)

    # Add node to new capabilities
    Enum.reduce(capabilities, cleaned_index, fn capability, acc ->
      Map.update(acc, capability, [node_id], fn existing ->
        [node_id | Enum.reject(existing, &(&1 == node_id))]
      end)
    end)
  end

  defp remove_from_capabilities_index(index, node_id) do
    Map.new(index, fn {capability, node_list} ->
      {capability, Enum.reject(node_list, &(&1 == node_id))}
    end)
  end

  defp cleanup_inactive_sessions(nodes) do
    cutoff_time = DateTime.utc_now() |> DateTime.add(-@session_timeout, :millisecond)

    inactive_nodes = nodes
    |> Enum.filter(fn {_node_id, node_data} ->
      case Map.get(node_data, :last_heartbeat) do
        nil -> true
        timestamp -> DateTime.compare(timestamp, cutoff_time) == :lt
      end
    end)
    |> Enum.map(fn {node_id, _} -> node_id end)

    # Remove inactive nodes
    Enum.each(inactive_nodes, &do_deregister_node/1)

    length(inactive_nodes)
  end

  defp refresh_state_from_db(state) do
    # Get current sessions from database
    active_sessions = Repo.all(NodeSession)

    nodes = active_sessions
    |> Enum.map(fn session ->
      {session.node_id, session_to_map(session)}
    end)
    |> Enum.into(%{})

    capabilities_index = active_sessions
    |> Enum.reduce(%{}, fn session, acc ->
      update_capabilities_index(acc, session.node_id, session.capabilities)
    end)

    %{state | nodes: nodes, capabilities_index: capabilities_index}
  end

  defp find_node_by_pid(nodes, target_pid) do
    case Enum.find(nodes, fn {_node_id, node_data} ->
      Map.get(node_data, :pid) == target_pid
    end) do
      {node_id, _} -> {:ok, node_id}
      nil -> :not_found
    end
  end

  defp session_to_response(session, pid) do
    %{
      node_id: session.node_id,
      status: session.status,
      session_token: session.session_token,
      capabilities: session.capabilities,
      privacy_budget: session.privacy_budget,
      registered_at: session.inserted_at,
      pid: pid
    }
  end

  defp session_to_map(session) do
    %{
      node_id: session.node_id,
      status: session.status,
      capabilities: session.capabilities,
      last_heartbeat: session.last_heartbeat,
      current_round_id: session.current_round_id,
      privacy_budget: session.privacy_budget
    }
  end

  defp extract_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_sessions, @cleanup_interval)
  end
end
