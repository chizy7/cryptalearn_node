defmodule CryptalearnNodeWeb.FallbackController do
  use CryptalearnNodeWeb, :controller

  @doc """
  Handle 404 errors for undefined routes.
  """
  def not_found(conn, _params) do
    conn
    |> put_status(404)
    |> json(%{
      error: "route_not_found",
      message: "The requested endpoint does not exist",
      path: conn.request_path,
      method: conn.method,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Handle validation errors from controllers.
  """
  def call(conn, {:error, :validation_failed, errors}) do
    conn
    |> put_status(400)
    |> json(%{
      error: "validation_failed",
      details: errors,
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(404)
    |> json(%{
      error: "resource_not_found",
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, {:error, :unauthorized}) do
    conn
    |> put_status(401)
    |> json(%{
      error: "unauthorized",
      message: "Authentication required",
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(403)
    |> json(%{
      error: "forbidden",
      message: "Access denied",
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(500)
    |> json(%{
      error: "internal_server_error",
      details: Atom.to_string(reason),
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn
    |> put_status(500)
    |> json(%{
      error: "internal_server_error",
      message: message,
      timestamp: DateTime.utc_now()
    })
  end

  def call(conn, _error) do
    conn
    |> put_status(500)
    |> json(%{
      error: "internal_server_error",
      message: "An unexpected error occurred",
      timestamp: DateTime.utc_now()
    })
  end
end
