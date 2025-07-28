defmodule CryptalearnNode.Repo.Migrations.CreateNodeSessions do
  use Ecto.Migration

  def change do
    create table(:node_sessions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, :string, null: false
      add :status, :string, null: false, default: "idle"
      add :capabilities, {:array, :string}, null: false, default: []
      add :public_key, :text
      add :session_token, :string
      add :last_heartbeat, :utc_datetime
      add :connection_info, :map, default: %{}
      add :privacy_budget, :map, default: %{"epsilon" => 1.0, "delta" => 1.0e-5}
      add :metadata, :map, default: %{}
      add :current_round_id, :string
      add :training_history, {:array, :map}, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:node_sessions, [:node_id])
    create index(:node_sessions, [:status])
    create index(:node_sessions, [:last_heartbeat])
    create index(:node_sessions, [:current_round_id])
  end
end
