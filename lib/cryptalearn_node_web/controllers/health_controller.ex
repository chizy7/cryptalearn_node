defmodule CryptalearnNodeWeb.HealthController do
  use CryptalearnNodeWeb, :controller

  @doc """
  Comprehensive health check endpoint for monitoring and load balancers.
  """
  def check(conn, _params) do
    health_status = %{
      status: "healthy",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      version: Application.spec(:cryptalearn_node, :vsn) |> to_string(),
      uptime: calculate_uptime(),
      system: %{
        memory: format_memory(:erlang.memory()),
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        run_queue: :erlang.statistics(:run_queue),
        cpu_count: System.schedulers_online()
      },
      services: %{
        database: check_database(),
        node_registry: check_node_registry()
      }
    }

    status_code = if all_services_healthy?(health_status.services) do
      200
    else
      503
    end

    conn
    |> put_status(status_code)
    |> json(health_status)
  end

  @doc """
  Simple liveness probe for Kubernetes.
  """
  def alive(conn, _params) do
    conn
    |> put_status(200)
    |> json(%{status: "alive", timestamp: DateTime.utc_now()})
  end

  @doc """
  Readiness probe that checks if the service can handle requests.
  """
  def ready(conn, _params) do
    ready = case check_database() do
      %{status: "healthy"} -> true
      _ -> false
    end

    status_code = if ready, do: 200, else: 503

    conn
    |> put_status(status_code)
    |> json(%{
      status: if(ready, do: "ready", else: "not_ready"),
      timestamp: DateTime.utc_now()
    })
  end

  # Private helper functions

  defp calculate_uptime do
    # Calculate uptime in seconds since the VM started
    :erlang.statistics(:wall_clock)
    |> elem(0)
    |> div(1000)
  end

  defp check_database do
    try do
      start_time = System.monotonic_time(:millisecond)

      case Ecto.Adapters.SQL.query(CryptalearnNode.Repo, "SELECT 1", []) do
        {:ok, _result} ->
          response_time = System.monotonic_time(:millisecond) - start_time
          %{
            status: "healthy",
            response_time_ms: response_time,
            pool_size: get_pool_size()
          }

        {:error, error} ->
          %{
            status: "unhealthy",
            error: "database_query_failed",
            details: inspect(error)
          }
      end
    rescue
      exception ->
        %{
          status: "unhealthy",
          error: "database_connection_failed",
          details: Exception.message(exception)
        }
    end
  end

  defp check_node_registry do
    try do
      # Check if the Registry is running and responsive
      case Registry.count(CryptalearnNode.NodeRegistry) do
        count when is_integer(count) ->
          %{
            status: "healthy",
            active_nodes: count
          }

        _ ->
          %{status: "unhealthy", error: "registry_not_responding"}
      end
    rescue
      _ ->
        %{status: "unhealthy", error: "registry_unavailable"}
    end
  end

  defp get_pool_size do
    config = CryptalearnNode.Repo.config()
    Keyword.get(config, :pool_size, "unknown")
  end

  defp all_services_healthy?(services) do
    Enum.all?(services, fn {_service, status} ->
      Map.get(status, :status) == "healthy"
    end)
  end

  defp format_memory(memory_info) do
    memory_info
    |> Map.new(fn {key, bytes} -> {key, format_bytes(bytes)} end)
  end

  defp format_bytes(bytes) when is_integer(bytes) do
    %{
      bytes: bytes,
      mb: Float.round(bytes / (1024 * 1024), 2),
      human: format_bytes_human(bytes)
    }
  end

  defp format_bytes_human(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)}GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)}MB"
      bytes >= 1024 -> "#{Float.round(bytes / 1024, 1)}KB"
      true -> "#{bytes}B"
    end
  end
end
