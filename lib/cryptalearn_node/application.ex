defmodule CryptalearnNode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      CryptalearnNodeWeb.Telemetry,

      # Start the Ecto repository
      CryptalearnNode.Repo,

      # Start the PubSub system
      {Phoenix.PubSub, name: CryptalearnNode.PubSub},

      # Start the Finch HTTP client for sending emails
      {Finch, name: CryptalearnNode.Finch},

      # Start the Registry for node sessions
      {Registry, keys: :unique, name: CryptalearnNode.NodeRegistry},

      # Start the DynamicSupervisor for session processes
      {DynamicSupervisor, strategy: :one_for_one, name: CryptalearnNode.Nodes.SessionSupervisor},

      # Start the Node Registry GenServer
      CryptalearnNode.Nodes.Registry,

      # Start DNS cluster for distributed deployment
      {DNSCluster, query: Application.get_env(:cryptalearn_node, :dns_cluster_query) || :ignore},

      # Start to serve requests, typically the last entry
      CryptalearnNodeWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CryptalearnNode.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CryptalearnNodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
