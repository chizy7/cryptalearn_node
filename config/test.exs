import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cryptalearn_node, CryptalearnNode.Repo,
  username: System.get_env("TEST_DB_USERNAME") || "postgres",
  password: System.get_env("TEST_DB_PASSWORD") || "postgres",
  hostname: "localhost",
  database: "cryptalearn_node_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cryptalearn_node, CryptalearnNodeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: System.get_env("TEST_SECRET_KEY_BASE") || "4b7zvcRzlxjEMkkFHYDFkFTG5xd2LPLOLH/9P0046DJ8P6qtbjgn+rUSPEsXz/OP",
  server: false

# In test we don't send emails
config :cryptalearn_node, CryptalearnNode.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
