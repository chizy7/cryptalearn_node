defmodule CryptalearnNode.Nodes.SessionManager do
  @moduledoc """
  GenServer that manages individual client node sessions.

  Each registered node gets its own SessionManager process that handles:
  - Session state management
  - Heartbeat monitoring
  - Training status updates
  - Privacy budget tracking
  """

  use GenServer, restart: :temporary
  require Logger

  alias CryptalearnNode.Nodes.NodeSession
  alias CryptalearnNode.Repo

  @heartbeat_timeout 300_000 # 5 minutes

  defstruct [
    :node_id,
    :session_data,
    :last_heartbeat,
    :heartbeat_timer_ref
  ]

  # Client API

  def start_link(opts) do
    node_id = Keyword.fetch!(opts, :node_id)
    session_data = Keyword.fetch!(opts, :session_data)

    GenServer.start_link(
      __MODULE__,
      %{node_id: node_id, session_data: session_data},
      name: via_tuple(node_id)
    )
  end

  @doc """
  Get the current status of the session.
  """
  def get_status(node_id) do
    try do
      GenServer.call(via_tuple(node_id), :get_status, 5000)
    catch
      :exit, {:noproc, _} -> {:error, :session_not_found}
      :exit, {:timeout, _} -> {:error, :session_timeout}
    end
  end

  @doc """
  Record a heartbeat from the client.
  """
  def heartbeat(node_id) do
    try do
      GenServer.cast(via_tuple(node_id), :heartbeat)
    catch
      :exit, {:noproc, _} -> {:error, :session_not_found}
    end
  end

  @doc """
  Update the training status for this session.
  """
  def update_training_status(node_id, round_id, status) do
    try do
      GenServer.cast(via_tuple(node_id), {:update_training_status, round_id, status})
    catch
      :exit, {:noproc, _} -> {:error, :session_not_found}
    end
  end

  @doc """
  Update the privacy budget after an operation.
  """
  def consume_privacy_budget(node_id, epsilon_used, delta_used) do
    try do
      GenServer.call(via_tuple(node_id), {:consume_privacy_budget, epsilon_used, delta_used})
    catch
      :exit, {:noproc, _} -> {:error, :session_not_found}
    end
  end

  @doc """
  Get the remaining privacy budget.
  """
  def get_privacy_budget(node_id) do
    try do
      GenServer.call(via_tuple(node_id), :get_privacy_budget)
    catch
      :exit, {:noproc, _} -> {:error, :session_not_found}
    end
  end

  # Server Callbacks

  def init(%{node_id: node_id, session_data: session_data}) do
    # Schedule initial heartbeat timeout
    timer_ref = schedule_heartbeat_timeout()

    state = %__MODULE__{
      node_id: node_id,
      session_data: session_data,
      last_heartbeat: session_data.last_heartbeat || DateTime.utc_now() |> DateTime.truncate(:second),
      heartbeat_timer_ref: timer_ref
    }

    Logger.info("Session started for node: #{node_id}")

    {:ok, state}
  end

  def handle_call(:get_status, _from, state) do
    response = %{
      node_id: state.node_id,
      status: state.session_data.status,
      last_heartbeat: state.last_heartbeat,
      current_round_id: state.session_data.current_round_id,
      privacy_budget: state.session_data.privacy_budget,
      capabilities: state.session_data.capabilities,
      session_age: session_age_seconds(state),
      is_active: is_session_active?(state)
    }

    {:reply, {:ok, response}, state}
  end

  def handle_call({:consume_privacy_budget, epsilon_used, delta_used}, _from, state) do
    case do_consume_privacy_budget(state, epsilon_used, delta_used) do
      {:ok, new_session_data} ->
        new_state = %{state | session_data: new_session_data}
        {:reply, {:ok, new_session_data.privacy_budget}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:get_privacy_budget, _from, state) do
    {:reply, {:ok, state.session_data.privacy_budget}, state}
  end

  def handle_cast(:heartbeat, state) do
    # Cancel existing timer
    if state.heartbeat_timer_ref do
      Process.cancel_timer(state.heartbeat_timer_ref)
    end

    # Update heartbeat in database
    case update_heartbeat_in_db(state.session_data) do
      {:ok, updated_session} ->
        # Schedule new timeout
        new_timer_ref = schedule_heartbeat_timeout()

        new_state = %{state |
          session_data: updated_session,
          last_heartbeat: DateTime.utc_now() |> DateTime.truncate(:second),
          heartbeat_timer_ref: new_timer_ref
        }

        Logger.debug("Heartbeat received from node: #{state.node_id}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to update heartbeat for node #{state.node_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_cast({:update_training_status, round_id, status}, state) do
    case update_training_status_in_db(state.session_data, round_id, status) do
      {:ok, updated_session} ->
        new_state = %{state | session_data: updated_session}

        Logger.info("Training status updated for node #{state.node_id}: #{status} (round: #{round_id})")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to update training status for node #{state.node_id}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:heartbeat_timeout, state) do
    Logger.warning("Heartbeat timeout for node: #{state.node_id}")

    # Mark session as offline in database
    case mark_session_offline(state.session_data) do
      {:ok, _} ->
        Logger.info("Marked session offline: #{state.node_id}")

      {:error, reason} ->
        Logger.error("Failed to mark session offline: #{inspect(reason)}")
    end

    # Terminate the session
    {:stop, :heartbeat_timeout, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("Session for node #{state.node_id} terminating: #{inspect(reason)}")
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    Logger.info("Session manager terminating for node #{state.node_id}: #{inspect(reason)}")

    # Clean up timer
    if state.heartbeat_timer_ref do
      Process.cancel_timer(state.heartbeat_timer_ref)
    end

    # Update session status in database
    case mark_session_offline(state.session_data) do
      {:ok, _} -> :ok
      {:error, error} ->
        Logger.error("Failed to update session status on termination: #{inspect(error)}")
    end

    :ok
  end

  # Private helper functions

  defp via_tuple(node_id) do
    {:via, Registry, {CryptalearnNode.NodeRegistry, node_id}}
  end

  defp schedule_heartbeat_timeout do
    Process.send_after(self(), :heartbeat_timeout, @heartbeat_timeout)
  end

  defp session_age_seconds(state) do
    DateTime.diff(DateTime.utc_now(), state.session_data.inserted_at, :second)
  end

  defp is_session_active?(state) do
    case state.last_heartbeat do
      nil -> false
      timestamp ->
        diff = DateTime.diff(DateTime.utc_now(), timestamp, :second)
        diff < 300 # Active if heartbeat within last 5 minutes
    end
  end

  defp do_consume_privacy_budget(state, epsilon_used, delta_used) do
    session = state.session_data

    changeset = NodeSession.privacy_budget_changeset(session, epsilon_used, delta_used)

    if changeset.valid? do
      case Repo.update(changeset) do
        {:ok, updated_session} ->
          # Log privacy budget consumption
          log_privacy_consumption(
            session.node_id,
            session.current_round_id,
            epsilon_used,
            delta_used,
            updated_session.privacy_budget
          )

          {:ok, updated_session}

        {:error, changeset} ->
          {:error, extract_changeset_errors(changeset)}
      end
    else
      {:error, extract_changeset_errors(changeset)}
    end
  end

  defp update_heartbeat_in_db(session) do
    changeset = NodeSession.heartbeat_changeset(session)
    Repo.update(changeset)
  end

  defp update_training_status_in_db(session, round_id, status) do
    attrs = %{
      status: status,
      current_round_id: round_id
    }

    changeset = NodeSession.training_status_changeset(session, attrs)
    Repo.update(changeset)
  end

  defp mark_session_offline(session) do
    changeset = NodeSession.training_status_changeset(session, %{status: "offline"})
    Repo.update(changeset)
  end

  defp log_privacy_consumption(node_id, round_id, epsilon_used, delta_used, remaining_budget) do
    # This would integrate with the PrivacyAuditLog schema
    # For now, just log to the application log
    Logger.info("Privacy budget consumed", %{
      node_id: node_id,
      round_id: round_id,
      epsilon_used: epsilon_used,
      delta_used: delta_used,
      epsilon_remaining: remaining_budget["epsilon"],
      delta_remaining: remaining_budget["delta"]
    })
  end

  defp extract_changeset_errors(changeset) do
    changeset.errors
    |> Enum.map(fn {field, {message, _}} -> "#{field}: #{message}" end)
    |> Enum.join(", ")
  end
end
