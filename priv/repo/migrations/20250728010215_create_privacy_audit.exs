defmodule CryptalearnNode.Repo.Migrations.CreatePrivacyAudit do
  use Ecto.Migration

  def change do
    create table(:privacy_audit_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :node_id, :string, null: false
      add :round_id, :string, null: false
      add :operation, :string, null: false # "training", "aggregation", "noise_addition"
      add :epsilon_used, :float, null: false
      add :delta_used, :float, null: false
      add :epsilon_remaining, :float, null: false
      add :delta_remaining, :float, null: false
      add :mechanism, :string # "gaussian", "laplace", etc.
      add :sensitivity, :float
      add :noise_scale, :float
      add :privacy_proof, :map # Cryptographic proof data
      add :compliance_status, :string, default: "compliant"

      timestamps(type: :utc_datetime)
    end

    create index(:privacy_audit_logs, [:node_id])
    create index(:privacy_audit_logs, [:round_id])
    create index(:privacy_audit_logs, [:operation])
    create index(:privacy_audit_logs, [:inserted_at])
    create index(:privacy_audit_logs, [:compliance_status])
  end
end
