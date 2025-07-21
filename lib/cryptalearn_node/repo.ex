defmodule CryptalearnNode.Repo do
  use Ecto.Repo,
    otp_app: :cryptalearn_node,
    adapter: Ecto.Adapters.Postgres
end
