defmodule CryptalearnNode.Repo.Migrations.CreateModelVersions do
  use Ecto.Migration

  def change do
    create table(:model_versions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :version, :string, null: false
      add :round_id, :string
      add :model_data, :binary, null: false
      add :architecture, :map, null: false
      add :metadata, :map, default: %{}
      add :size_bytes, :integer
      add :checksum, :string, null: false
      add :created_by, :string # Which aggregation process
      add :is_current, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:model_versions, [:version])
    create index(:model_versions, [:round_id])
    create index(:model_versions, [:is_current])
    create index(:model_versions, [:inserted_at])
  end
end
