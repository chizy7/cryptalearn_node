defmodule CryptalearnNode.Repo.Migrations.CreateTrainingRounds do
  use Ecto.Migration

  def change do
    create table(:training_rounds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :round_id, :string, null: false
      add :status, :string, null: false, default: "waiting"
      add :global_model_version, :string
      add :participants, {:array, :string}, default: []
      add :required_participants, :integer, null: false
      add :collected_updates, :map, default: %{}
      add :training_config, :map, null: false
      add :privacy_params, :map, null: false
      add :started_at, :utc_datetime
      add :deadline, :utc_datetime
      add :completed_at, :utc_datetime
      add :aggregation_result, :map

      timestamps(type: :utc_datetime)
    end

    create unique_index(:training_rounds, [:round_id])
    create index(:training_rounds, [:status])
    create index(:training_rounds, [:started_at])
    create index(:training_rounds, [:deadline])
  end
end
