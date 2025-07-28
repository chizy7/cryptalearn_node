defmodule CryptalearnNodeWeb.NodeControllerTest do
  # Disable async to ensure proper database access across processes
  use CryptalearnNodeWeb.ConnCase, async: false

  alias CryptalearnNode.Nodes.{Registry, NodeSession}
  alias CryptalearnNode.Repo
  
  # Global setup for all tests to ensure the Registry GenServer has DB access
  setup do
    # Ensure the Registry GenServer is started
    {:ok, _} = Application.ensure_all_started(:cryptalearn_node)
    
    # Get the Registry process
    registry_pid = Process.whereis(CryptalearnNode.Nodes.Registry)
    
    if registry_pid do
      # Allow the Registry process to access the database
      Ecto.Adapters.SQL.Sandbox.allow(CryptalearnNode.Repo, self(), registry_pid)
    end
    
    :ok
  end

  describe "POST /api/v1/nodes/register" do
    test "successfully registers a new node", %{conn: conn} do
      node_params = %{
        "node_id" => "test-node-#{:rand.uniform(10000)}",
        "capabilities" => ["fl", "dp"],
        "public_key" => "test-public-key",
        "metadata" => %{
          "client_version" => "1.0.0",
          "architecture" => "x86_64"
        }
      }

      conn = post(conn, ~p"/api/v1/nodes/register", node_params)

      assert %{
        "status" => "registered",
        "node_id" => node_id,
        "session_token" => session_token,
        "capabilities" => ["fl", "dp"],
        "privacy_budget" => %{"epsilon" => 1.0, "delta" => 1.0e-5}
      } = json_response(conn, 201)

      assert node_id == node_params["node_id"]
      assert is_binary(session_token)

      # Verify node was created in database
      node_session = Repo.get_by(NodeSession, node_id: node_id)
      assert node_session != nil
      assert node_session.capabilities == ["fl", "dp"]
    end

    test "validates required parameters", %{conn: conn} do
      invalid_params = %{"capabilities" => ["fl"]}

      conn = post(conn, ~p"/api/v1/nodes/register", invalid_params)

      assert %{
        "error" => "validation_failed",
        "details" => details
      } = json_response(conn, 400)

      assert "node_id is required" in details
    end

    test "validates capability values", %{conn: conn} do
      invalid_params = %{
        "node_id" => "test-node",
        "capabilities" => ["fl", "invalid_capability"]
      }

      conn = post(conn, ~p"/api/v1/nodes/register", invalid_params)

      assert %{
        "error" => "validation_failed",
        "details" => details
      } = json_response(conn, 400)

      assert Enum.any?(details, &String.contains?(&1, "invalid capabilities"))
    end

    test "handles duplicate node registration", %{conn: conn} do
      node_id = "duplicate-test-node"

      node_params = %{
        "node_id" => node_id,
        "capabilities" => ["fl"]
      }

      # First registration
      conn1 = post(conn, ~p"/api/v1/nodes/register", node_params)
      assert json_response(conn1, 201)

      # Second registration with same node_id
      conn2 = post(conn, ~p"/api/v1/nodes/register", node_params)
      response = json_response(conn2, 201)

      # Should succeed and return updated session
      assert response["status"] == "registered"
      assert response["node_id"] == node_id
    end
  end

  describe "GET /api/v1/nodes/:node_id/status" do
    setup do
      {:ok, session_data} = Registry.register_node("status-test-node", %{
        capabilities: ["fl", "he"]
      })

      %{node_id: session_data.node_id}
    end

    test "returns node status for existing node", %{conn: conn, node_id: node_id} do
      conn = get(conn, ~p"/api/v1/nodes/#{node_id}/status")

      assert %{
        "node_id" => ^node_id,
        "status" => status,
        "capabilities" => capabilities,
        "privacy_budget" => privacy_budget
      } = json_response(conn, 200)

      assert status in ["idle", "training", "updating", "aggregating", "offline"]
      assert "fl" in capabilities
      assert "he" in capabilities
      assert is_map(privacy_budget)
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/nodes/non-existent-node/status")

      assert %{
        "error" => "node_not_found",
        "node_id" => "non-existent-node"
      } = json_response(conn, 404)
    end
  end

  describe "POST /api/v1/nodes/:node_id/heartbeat" do
    setup do
      {:ok, session_data} = Registry.register_node("heartbeat-test-node", %{
        capabilities: ["fl"]
      })

      %{node_id: session_data.node_id}
    end

    test "accepts heartbeat from registered node", %{conn: conn, node_id: node_id} do
      conn = post(conn, ~p"/api/v1/nodes/#{node_id}/heartbeat")

      assert %{
        "status" => "heartbeat_received",
        "node_id" => ^node_id,
        "timestamp" => _timestamp
      } = json_response(conn, 200)
    end

    test "rejects heartbeat from unregistered node", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/nodes/unregistered-node/heartbeat")

      assert %{
        "error" => "session_not_found",
        "node_id" => "unregistered-node"
      } = json_response(conn, 404)
    end
  end

  describe "GET /api/v1/nodes" do
    setup do
      # Register multiple nodes with different capabilities
      {:ok, _} = Registry.register_node("list-test-node-1", %{capabilities: ["fl"]})
      {:ok, _} = Registry.register_node("list-test-node-2", %{capabilities: ["fl", "he"]})
      {:ok, _} = Registry.register_node("list-test-node-3", %{capabilities: ["dp"]})

      :ok
    end

    test "lists all active nodes", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/nodes")

      assert %{
        "nodes" => nodes,
        "count" => count,
        "timestamp" => _timestamp
      } = json_response(conn, 200)

      assert is_map(nodes)
      assert count >= 3
      assert Map.has_key?(nodes, "list-test-node-1")
      assert Map.has_key?(nodes, "list-test-node-2")
      assert Map.has_key?(nodes, "list-test-node-3")
    end

    test "filters nodes by capability", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/nodes?capability=he")

      assert %{
        "nodes" => nodes,
        "count" => count,
        "filtered_by_capability" => "he"
      } = json_response(conn, 200)

      # Should only return nodes with "he" capability
      assert count >= 1
      assert Map.has_key?(nodes, "list-test-node-2")
      refute Map.has_key?(nodes, "list-test-node-1") # Only has "fl"
      refute Map.has_key?(nodes, "list-test-node-3") # Only has "dp"
    end
  end

  describe "DELETE /api/v1/nodes/:node_id" do
    setup do
      {:ok, session_data} = Registry.register_node("delete-test-node", %{
        capabilities: ["fl"]
      })

      %{node_id: session_data.node_id}
    end

    test "successfully deregisters a node", %{conn: conn, node_id: node_id} do
      conn = delete(conn, ~p"/api/v1/nodes/#{node_id}")

      assert %{
        "status" => "deregistered",
        "node_id" => ^node_id
      } = json_response(conn, 200)

      # Verify node was removed from database
      assert Repo.get_by(NodeSession, node_id: node_id) == nil
    end
  end

  describe "GET /api/v1/health" do
    test "returns healthy status", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/health")

      assert %{
        "status" => "healthy",
        "version" => _version,
        "uptime" => uptime,
        "system" => system,
        "services" => services
      } = json_response(conn, 200)

      assert is_number(uptime)
      assert is_map(system)
      assert is_map(services)
      assert Map.has_key?(services, "database")
      assert Map.has_key?(services, "node_registry")
    end
  end
end
