defmodule CryptalearnNodeWeb.NodeController do
  use CryptalearnNodeWeb, :controller

  alias CryptalearnNode.Nodes.Registry, as: NodeRegistry
  alias CryptalearnNode.Nodes.SessionManager



  require Logger

  defp try_register_node(node_id, params) do
    try do
      GenServer.call(NodeRegistry, {:register_node, node_id, params}, 30000) # 30 second timeout
    catch
      :exit, {:timeout, _} ->
        Logger.error("GenServer call timed out for node registration: #{node_id}")
        {:error, "registration_timeout"}
      :exit, {:noproc, _} ->
        Logger.error("GenServer not available for node registration: #{node_id}")
        {:error, "registry_unavailable"}
      :exit, reason ->
        Logger.error("GenServer call failed for node registration: #{node_id}, reason: #{inspect(reason)}")
        {:error, "registration_failed"}
    end
  end



  @doc """
  Register a new node in the federated learning network.

  POST /api/v1/nodes/register
  """
  def register(conn, params) do
    with {:ok, validated_params} <- validate_registration_params(params),
         {:ok, session_data} <- try_register_node(validated_params.node_id, validated_params) do

      Logger.info("Node registered successfully: #{validated_params.node_id}")

      response = %{
        status: "registered",
        node_id: session_data.node_id,
        session_token: session_data.session_token,
        capabilities: session_data.capabilities,
        privacy_budget: session_data.privacy_budget,
        registered_at: session_data.registered_at
      }

      conn
      |> put_status(201)
      |> json(response)
    else
      {:error, :validation_failed, errors} ->
        conn
        |> put_status(400)
        |> json(%{error: "validation_failed", details: errors})

      {:error, reason} when is_binary(reason) ->
        conn
        |> put_status(400)
        |> json(%{error: reason})

      {:error, reason} ->
        Logger.error("Node registration failed: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "registration_failed", details: "Internal server error"})
    end
  end

  @doc """
  Get the status of a specific node.

  GET /api/v1/nodes/:node_id/status
  """
  def status(conn, %{"node_id" => node_id}) do
    with {:ok, node_status} <- NodeRegistry.get_node_status(node_id) do
      conn
      |> put_status(200)
      |> json(node_status)
    else
      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "node_not_found", node_id: node_id})

      {:error, reason} ->
        Logger.error("Failed to get node status for #{node_id}: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "status_fetch_failed"})
    end
  end

  @doc """
  Deregister a node from the network.

  DELETE /api/v1/nodes/:node_id
  """
  def deregister(conn, %{"node_id" => node_id}) do
    case NodeRegistry.deregister_node(node_id) do
      :ok ->
        Logger.info("Node deregistered: #{node_id}")

        conn
        |> put_status(200)
        |> json(%{status: "deregistered", node_id: node_id})

      {:error, reason} ->
        Logger.error("Failed to deregister node #{node_id}: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "deregistration_failed", details: inspect(reason)})
    end
  end

  @doc """
  Send a heartbeat to maintain the session.

  POST /api/v1/nodes/:node_id/heartbeat
  """
  def heartbeat(conn, %{"node_id" => node_id}) do
    # First check if the node is registered
    case NodeRegistry.get_node_status(node_id) do
      {:ok, _node_status} ->
        # Node exists, process the heartbeat
        NodeRegistry.heartbeat(node_id)
        
        conn
        |> put_status(200)
        |> json(%{
          status: "heartbeat_received",
          node_id: node_id,
          timestamp: DateTime.utc_now()
        })
      
      {:error, :not_found} ->
        # Node doesn't exist, return 404
        Logger.warning("Received heartbeat from unregistered node: #{node_id}")
        
        conn
        |> put_status(404)
        |> json(%{
          error: "session_not_found",
          node_id: node_id
        })
        
      {:error, reason} ->
        # Other error, return 500
        Logger.error("Error processing heartbeat for node #{node_id}: #{inspect(reason)}")
        
        conn
        |> put_status(500)
        |> json(%{
          error: "heartbeat_failed",
          details: "Internal server error"
        })
    end
  end

  @doc """
  List all active nodes in the network.

  GET /api/v1/nodes
  """
  def list(conn, params) do
    capability_filter = Map.get(params, "capability")

    result = case capability_filter do
      nil ->
        NodeRegistry.list_active_nodes()

      capability ->
        NodeRegistry.get_nodes_by_capability(capability)
    end

    case result do
      {:ok, nodes} ->
        response = %{
          nodes: nodes,
          count: map_size(nodes),
          timestamp: DateTime.utc_now()
        }

        response = if capability_filter do
          Map.put(response, :filtered_by_capability, capability_filter)
        else
          response
        end

        conn
        |> put_status(200)
        |> json(response)

      {:error, reason} ->
        Logger.error("Failed to list nodes: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "list_nodes_failed"})
    end
  end

  @doc """
  Update the training status of a node.

  PATCH /api/v1/nodes/:node_id/training_status
  """
  def update_training_status(conn, %{"node_id" => node_id} = params) do
    with {:ok, round_id} <- extract_param(params, "round_id"),
         {:ok, status} <- extract_param(params, "status"),
         :ok <- validate_training_status(status) do

      NodeRegistry.update_training_status(node_id, round_id, status)

      conn
      |> put_status(200)
      |> json(%{
        status: "training_status_updated",
        node_id: node_id,
        round_id: round_id,
        new_status: status,
        timestamp: DateTime.utc_now()
      })
    else
      {:error, :missing_param, param} ->
        conn
        |> put_status(400)
        |> json(%{error: "missing_required_parameter", parameter: param})

      {:error, :invalid_status, status} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_training_status", provided: status, valid_statuses: valid_training_statuses()})
    end
  end

  @doc """
  Get the privacy budget for a node.

  GET /api/v1/nodes/:node_id/privacy_budget
  """
  def privacy_budget(conn, %{"node_id" => node_id}) do
    case SessionManager.get_privacy_budget(node_id) do
      {:ok, budget} ->
        conn
        |> put_status(200)
        |> json(%{
          node_id: node_id,
          privacy_budget: budget,
          timestamp: DateTime.utc_now()
        })

      {:error, :session_not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "session_not_found", node_id: node_id})

      {:error, reason} ->
        Logger.error("Failed to get privacy budget for #{node_id}: #{inspect(reason)}")

        conn
        |> put_status(500)
        |> json(%{error: "privacy_budget_fetch_failed"})
    end
  end

  # Private helper functions

  defp validate_registration_params(params) do
    errors = []

    # Validate node_id
    errors = case Map.get(params, "node_id") do
      nil -> ["node_id is required" | errors]
      "" -> ["node_id cannot be empty" | errors]
      node_id when is_binary(node_id) and byte_size(node_id) > 100 ->
        ["node_id must be 100 characters or less" | errors]
      _valid -> errors
    end

    # Validate capabilities
    errors = case Map.get(params, "capabilities") do
      nil -> ["capabilities are required" | errors]
      [] -> ["capabilities cannot be empty" | errors]
      capabilities when is_list(capabilities) ->
        valid_capabilities = ["fl", "he", "dp"]
        invalid_caps = capabilities -- valid_capabilities

        if Enum.empty?(invalid_caps) do
          errors
        else
          ["invalid capabilities: #{Enum.join(invalid_caps, ", ")}" | errors]
        end

      _ -> ["capabilities must be a list" | errors]
    end

    # Validate public_key (optional)
    errors = case Map.get(params, "public_key") do
      nil -> errors
      "" -> ["public_key cannot be empty if provided" | errors]
      key when is_binary(key) and byte_size(key) > 10000 ->
        ["public_key is too large" | errors]
      _valid -> errors
    end

    # Validate metadata (optional)
    errors = case Map.get(params, "metadata") do
      nil -> errors
      metadata when is_map(metadata) -> errors
      _ -> ["metadata must be a map" | errors]
    end

    if Enum.empty?(errors) do
      validated_params = %{
        node_id: Map.get(params, "node_id"),
        capabilities: Map.get(params, "capabilities"),
        public_key: Map.get(params, "public_key"),
        metadata: Map.get(params, "metadata", %{}),
        connection_info: extract_connection_info(params)
      }

      {:ok, validated_params}
    else
      {:error, :validation_failed, Enum.reverse(errors)}
    end
  end

  defp extract_connection_info(params) do
    %{
      user_agent: Map.get(params, "user_agent"),
      client_version: get_in(params, ["metadata", "client_version"]),
      architecture: get_in(params, ["metadata", "architecture"]),
      registration_time: DateTime.utc_now()
    }
  end

  defp extract_param(params, key) do
    case Map.get(params, key) do
      nil -> {:error, :missing_param, key}
      "" -> {:error, :missing_param, key}
      value -> {:ok, value}
    end
  end

  defp validate_training_status(status) do
    valid_statuses = valid_training_statuses()

    if status in valid_statuses do
      :ok
    else
      {:error, :invalid_status, status}
    end
  end

  defp valid_training_statuses do
    ["idle", "training", "updating", "aggregating", "offline"]
  end
end
