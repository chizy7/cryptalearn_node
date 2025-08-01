defmodule CryptalearnNodeWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CryptalearnNodeWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint CryptalearnNodeWeb.Endpoint

      use CryptalearnNodeWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import CryptalearnNodeWeb.ConnCase
    end
  end

  setup tags do
    pid = CryptalearnNode.DataCase.setup_sandbox(tags)
    
    # Allow the test process to use the connection
    Ecto.Adapters.SQL.Sandbox.allow(CryptalearnNode.Repo, self(), pid)
    
    # For tests involving GenServers that need DB access
    if registry_pid = Process.whereis(CryptalearnNode.Nodes.Registry) do
      Ecto.Adapters.SQL.Sandbox.allow(CryptalearnNode.Repo, registry_pid, pid)
    end
    
    # Set the pool to shared mode if the test is not running async
    if not tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(CryptalearnNode.Repo, {:shared, pid})
    end

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
