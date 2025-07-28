defmodule CryptalearnNode.Rounds.TrainingRound do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(waiting training aggregating completed failed)

  schema "training_rounds" do
    field :round_id, :string
    field :status, :string, default: "waiting"
    field :global_model_version, :string
    field :participants, {:array, :string}, default: []
    field :required_participants, :integer
    field :collected_updates, :map, default: %{}
    field :training_config, :map
    field :privacy_params, :map
    field :started_at, :utc_datetime
    field :deadline, :utc_datetime
    field :completed_at, :utc_datetime
    field :aggregation_result, :map

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for starting a new training round.
  """
  def start_changeset(training_round, attrs \\ %{}) do
    training_round
    |> cast(attrs, [
      :round_id, :participants, :required_participants,
      :training_config, :privacy_params, :global_model_version,
      :deadline
    ])
    |> validate_required([
      :round_id, :participants, :required_participants,
      :training_config, :privacy_params
    ])
    |> validate_number(:required_participants, greater_than: 0)
    |> validate_participants()
    |> validate_training_config()
    |> validate_privacy_params()
    |> unique_constraint(:round_id)
    |> put_started_at()
    |> put_deadline_if_missing()
  end

  @doc """
  Updates the round status.
  """
  def status_changeset(training_round, new_status) do
    training_round
    |> change()
    |> put_change(:status, new_status)
    |> validate_inclusion(:status, @valid_statuses)
    |> maybe_put_completed_at(new_status)
  end

  @doc """
  Adds a model update from a participant.
  """
  def add_update_changeset(training_round, node_id, update) do
    current_updates = training_round.collected_updates || %{}
    new_updates = Map.put(current_updates, node_id, update)

    training_round
    |> change()
    |> put_change(:collected_updates, new_updates)
    |> validate_participant_update(node_id)
  end

  @doc """
  Sets the aggregation result when round completes.
  """
  def complete_changeset(training_round, aggregation_result) do
    training_round
    |> change()
    |> put_change(:status, "completed")
    |> put_change(:aggregation_result, aggregation_result)
    |> put_change(:completed_at, DateTime.utc_now())
  end

  @doc """
  Checks if the round has enough updates to proceed with aggregation.
  """
  def ready_for_aggregation?(training_round) do
    update_count = map_size(training_round.collected_updates || %{})
    update_count >= training_round.required_participants
  end

  @doc """
  Checks if the round has timed out.
  """
  def timed_out?(training_round) do
    case training_round.deadline do
      nil -> false
      deadline -> DateTime.compare(DateTime.utc_now(), deadline) == :gt
    end
  end

  @doc """
  Gets the participation rate for this round.
  """
  def participation_rate(training_round) do
    total_participants = length(training_round.participants || [])
    actual_participants = map_size(training_round.collected_updates || %{})

    if total_participants > 0 do
      actual_participants / total_participants
    else
      0.0
    end
  end

  # Private helper functions

  defp validate_participants(changeset) do
    validate_change(changeset, :participants, fn :participants, participants ->
      required = get_field(changeset, :required_participants)

      cond do
        not is_list(participants) ->
          [participants: "must be a list"]

        Enum.empty?(participants) ->
          [participants: "cannot be empty"]

        required && length(participants) < required ->
          [participants: "must have at least #{required} participants"]

        true ->
          []
      end
    end)
  end

  defp validate_training_config(changeset) do
    validate_change(changeset, :training_config, fn :training_config, config ->
      required_keys = ["batch_size", "learning_rate", "epochs"]
      missing_keys = required_keys -- Map.keys(config || %{})

      cond do
        not is_map(config) ->
          [training_config: "must be a map"]

        not Enum.empty?(missing_keys) ->
          [training_config: "missing required keys: #{Enum.join(missing_keys, ", ")}"]

        not is_integer(config["batch_size"]) or config["batch_size"] <= 0 ->
          [training_config: "batch_size must be a positive integer"]

        not is_number(config["learning_rate"]) or config["learning_rate"] <= 0 ->
          [training_config: "learning_rate must be a positive number"]

        not is_integer(config["epochs"]) or config["epochs"] <= 0 ->
          [training_config: "epochs must be a positive integer"]

        true ->
          []
      end
    end)
  end

  defp validate_privacy_params(changeset) do
    validate_change(changeset, :privacy_params, fn :privacy_params, params ->
      required_keys = ["epsilon", "delta"]
      missing_keys = required_keys -- Map.keys(params || %{})

      cond do
        not is_map(params) ->
          [privacy_params: "must be a map"]

        not Enum.empty?(missing_keys) ->
          [privacy_params: "missing required keys: #{Enum.join(missing_keys, ", ")}"]

        not is_number(params["epsilon"]) or params["epsilon"] <= 0 ->
          [privacy_params: "epsilon must be a positive number"]

        not is_number(params["delta"]) or params["delta"] <= 0 ->
          [privacy_params: "delta must be a positive number"]

        true ->
          []
      end
    end)
  end

  defp validate_participant_update(changeset, node_id) do
    participants = get_field(changeset, :participants) || []

    if node_id in participants do
      changeset
    else
      add_error(changeset, :collected_updates, "node #{node_id} is not a participant in this round")
    end
  end

  defp put_started_at(changeset) do
    put_change(changeset, :started_at, DateTime.utc_now())
  end

  defp put_deadline_if_missing(changeset) do
    if get_field(changeset, :deadline) do
      changeset
    else
      # Default to 10 minutes from now
      deadline = DateTime.utc_now() |> DateTime.add(600, :second)
      put_change(changeset, :deadline, deadline)
    end
  end

  defp maybe_put_completed_at(changeset, status) when status in ["completed", "failed"] do
    put_change(changeset, :completed_at, DateTime.utc_now())
  end

  defp maybe_put_completed_at(changeset, _status), do: changeset
end
