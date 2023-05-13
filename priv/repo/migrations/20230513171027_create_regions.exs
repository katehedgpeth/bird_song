defmodule BirdSong.Repo.Migrations.CreateRegions do
  use Ecto.Migration

  def change do
    create table(:regions) do
      add :code, :string
      add :short_name, :string
      add :full_name, :string
      add :min_lat, :float
      add :max_lat, :float
      add :min_lon, :float
      add :max_lon, :float
      add :level, :string

      timestamps()
    end

    create unique_index(:regions, [:full_name])
    create unique_index(:regions, [:code])
  end
end
