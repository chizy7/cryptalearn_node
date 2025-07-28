defmodule CryptalearnNodeWeb.Router do
  use CryptalearnNodeWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
    # TODO: Add JWT authentication plug
    # plug CryptalearnNodeWeb.Plugs.Authenticate
  end

  # Public API routes
  scope "/api/v1", CryptalearnNodeWeb do
    pipe_through :api

    # Health and system status
    get "/health", HealthController, :check
    get "/health/alive", HealthController, :alive
    get "/health/ready", HealthController, :ready



    # Node registration (public endpoint)
    post "/nodes/register", NodeController, :register
  end

  # Authenticated API routes
  scope "/api/v1", CryptalearnNodeWeb do
    pipe_through :authenticated_api

    # Node management
    get "/nodes", NodeController, :list
    get "/nodes/:node_id/status", NodeController, :status
    delete "/nodes/:node_id", NodeController, :deregister
    post "/nodes/:node_id/heartbeat", NodeController, :heartbeat
    patch "/nodes/:node_id/training_status", NodeController, :update_training_status
    get "/nodes/:node_id/privacy_budget", NodeController, :privacy_budget

    # Training rounds (TODO: implement next)
    # get "/rounds/current", RoundController, :current
    # post "/rounds/:round_id/updates", RoundController, :submit_update
    # get "/rounds/:round_id/status", RoundController, :status

    # Model management (TODO: implement next)
    # get "/models/current", ModelController, :current
    # get "/models/:version", ModelController, :get_version
    # get "/models/:version/download", ModelController, :download
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:cryptalearn_node, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: CryptalearnNodeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Catch-all for undefined routes
  scope "/", CryptalearnNodeWeb do
    pipe_through :api

    match :*, "/*path", FallbackController, :not_found
  end
end
