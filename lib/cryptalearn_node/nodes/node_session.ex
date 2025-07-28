defmodule CryptalearnNode.Nodes.NodeSession do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(idle training updating aggregating offline)
  @valid_capabilities ~w(fl he dp)

  schema "node_sessions" do
    field :node_id, :string
    field :status, :string, default: "idle"
    field :capabilities, {:array, :string}, default: []
    field :public_key, :string
    field :session_token, :string
    field :last_heartbeat, :utc_datetime
    field :connection_info, :map, default: %{}
    field :privacy_budget, :map, default: %{"epsilon" => 1.0, "delta" => 1.0e-5}
    field :metadata, :map, default: %{}
    field :current_round_id, :string
    field :training_history, {:array, :map}, default: []

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for node registration.
  """
  def registration_changeset(node_session, attrs \\ %{}) do
    node_session
    |> cast(attrs, [
      :node_id, :capabilities, :public_key, :metadata,
      :connection_info, :privacy_budget
    ])
    |> validate_required([:node_id, :capabilities])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_capabilities()
    |> validate_privacy_budget()
    |> unique_constraint(:node_id)
    |> put_session_token()
    |> put_last_heartbeat()
  end

  @doc """
  Updates the heartbeat timestamp.
  """
  def heartbeat_changeset(node_session, attrs \\ %{}) do
    node_session
    |> cast(attrs, [:last_heartbeat])
    |> put_change(:last_heartbeat, DateTime.utc_now())
  end

  @doc """
  Updates the training status and current round.
  """
  def training_status_changeset(node_session, attrs) do
    node_session
    |> cast(attrs, [:status, :current_round_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_add_to_history()
  end

  @doc """
  Updates privacy budget after an operation.
  """
  def privacy_budget_changeset(node_session, epsilon_used, delta_used) do
    current_budget = node_session.privacy_budget || %{"epsilon" => 1.0, "delta" => 1.0e-5}

    new_epsilon = current_budget["epsilon"] - epsilon_used
    new_delta = current_budget["delta"] - delta_used

    new_budget = %{
      "epsilon" => max(0.0, new_epsilon),
      "delta" => max(0.0, new_delta)
    }

    node_session
    |> change()
    |> put_change(:privacy_budget, new_budget)
    |> validate_privacy_budget_positive()
  end

  # Private helper functions

  defp validate_capabilities(changeset) do
    validate_change(changeset, :capabilities, fn :capabilities, capabilities ->
      invalid_caps = capabilities -- @valid_capabilities

      if Enum.empty?(invalid_caps) do
        []
      else
        [capabilities: "invalid capabilities: #{Enum.join(invalid_caps, ", ")}"]
      end
    end)
  end

  defp validate_privacy_budget(changeset) do
    validate_change(changeset, :privacy_budget, fn :privacy_budget, budget ->
      cond do
        not is_map(budget) ->
          [privacy_budget: "must be a map"]

        not Map.has_key?(budget, "epsilon") or not Map.has_key?(budget, "delta") ->
          [privacy_budget: "must contain epsilon and delta"]

        not is_number(budget["epsilon"]) or not is_number(budget["delta"]) ->
          [privacy_budget: "epsilon and delta must be numbers"]

        budget["epsilon"] < 0 or budget["delta"] < 0 ->
          [privacy_budget: "epsilon and delta must be non-negative"]

        true ->
          []
      end
    end)
  end

  defp validate_privacy_budget_positive(changeset) do
    budget = get_change(changeset, :privacy_budget)

    if budget && (budget["epsilon"] < 0 or budget["delta"] < 0) do
      add_error(changeset, :privacy_budget, "insufficient privacy budget remaining")
    else
      changeset
    end
  end

  defp put_session_token(changeset) do
    if changeset.valid? do
      token = generate_session_token()
      put_change(changeset, :session_token, token)
    else
      changeset
    end
  end

  defp put_last_heartbeat(changeset) do
    # Truncate microseconds to avoid database compatibility issues
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    put_change(changeset, :last_heartbeat, now)
  end

  defp maybe_add_to_history(changeset) do
    if get_change(changeset, :status) do
      current_history = changeset.data.training_history || []

      history_entry = %{
        "status" => get_change(changeset, :status),
        "round_id" => get_change(changeset, :current_round_id),
        "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }

      new_history = [history_entry | current_history] |> Enum.take(50) # Keep last 50 entries
      put_change(changeset, :training_history, new_history)
    else
      changeset
    end
  end

  defp generate_session_token do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end
end
