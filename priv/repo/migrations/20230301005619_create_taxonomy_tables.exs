defmodule BirdSong.Repo.Migrations.CreateTaxonomyTables do
  use Ecto.Migration

  def change do
    create_orders()
    create_families()
    create_birds()
  end

  def create_orders() do
    create table(:orders) do
      add :name, :string, null: false
    end

    create unique_index(:orders, [:name])
  end

  def create_families() do
    create table(:families) do
      add :common_name, :string, null: false
      add :code, :string, null: false
      add :sci_name, :string, null: false
      add :order_id, references(:orders), null: false
    end

    create unique_index(:families, [:common_name])
    create unique_index(:families, [:code])
    create unique_index(:families, [:sci_name])
  end

  def create_birds() do
    create table(:birds) do
      # unique
      add :species_code, :string, null: false
      add :common_name, :string, null: false
      add :sci_name, :string, null: false
      add :taxon_order, :float, null: false

      # not unique
      add :category, :string, null: false
      add :report_as, :string
      add :banding_codes, {:array, :string}, default: [], null: false
      add :common_name_codes, {:array, :string}, default: [], null: false
      add :sci_name_codes, {:array, :string}, default: [], null: false
      add :has_recordings?, :boolean, default: false, null: false
      add :has_images?, :boolean, default: false, null: false
      add :family_id, references(:families), null: false
      add :order_id, references(:orders), null: false
    end

    create unique_index(:birds, [:species_code])
    create unique_index(:birds, [:common_name])
    create unique_index(:birds, [:sci_name])
    create unique_index(:birds, [:taxon_order])
  end
end
