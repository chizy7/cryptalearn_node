# Ensure the application and its dependencies are started
Application.ensure_all_started(:cryptalearn_node)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(CryptalearnNode.Repo, :manual)
