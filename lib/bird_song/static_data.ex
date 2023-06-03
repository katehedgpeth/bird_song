defmodule BirdSong.StaticData do
  def seed!("" <> data_folder_path \\ "data") do
    seed_taxonomy(data_folder_path)
    seed_regions(data_folder_path)
    :ok
  end

  def seed_taxonomy(data_folder_path) do
    data_folder_path
    |> Path.join("taxonomy.json")
    |> BirdSong.Services.Ebird.Taxonomy.read_data_file()
    |> Enum.chunk_every(1_000)
    |> Enum.map(&BirdSong.Services.Ebird.Taxonomy.seed!/1)
  end

  def seed_regions(data_folder_path) do
    Mix.Tasks.BirdSong.SeedRegions.run(%{folder: data_folder_path})
  end
end
