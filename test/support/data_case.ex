defmodule CryptalearnNode.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use CryptalearnNode.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias CryptalearnNode.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import CryptalearnNode.DataCase
    end
  end

  setup tags do
    CryptalearnNode.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    # Ensure application is started before trying to access repo
    {:ok, _} = Application.ensure_all_started(:cryptalearn_node)
    
    # Use try/rescue to handle potential database connection issues
    try do
      pid = Ecto.Adapters.SQL.Sandbox.start_owner!(CryptalearnNode.Repo, shared: not tags[:async])
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
      pid
    rescue
      e in RuntimeError ->
        IO.puts("Error starting database connection: #{inspect(e)}")
        # Fall back to manual checkout
        :ok = Ecto.Adapters.SQL.Sandbox.checkout(CryptalearnNode.Repo)
        on_exit(fn -> Ecto.Adapters.SQL.Sandbox.checkin(CryptalearnNode.Repo) end)
        nil
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
