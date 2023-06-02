defmodule BirdSong.StaticData do
  alias Ecto.Multi

  alias BirdSong.Services

  def seed!("" <> data_folder_path \\ "data") do
    data_folder_path
    |> seed_taxonomy()
    |> Multi.append(seed_regions(data_folder_path))
    |> BirdSong.Repo.transaction()
    |> case do
      {:ok, changes} -> changes
      {:error, error} -> raise error
    end
  end

  def seed_taxonomy(data_folder_path) do
    data_folder_path
    |> Path.join("taxonomy.json")
    |> BirdSong.Services.Ebird.Taxonomy.read_data_file()
    |> BirdSong.Services.Ebird.Taxonomy.seed()
  end

  def seed_regions(data_folder_path) do
    Mix.Tasks.BirdSong.SeedRegions.run(%{folder: data_folder_path, run_transaction?: false})
  end
end
