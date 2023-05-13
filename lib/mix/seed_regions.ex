defmodule Mix.Tasks.BirdSong.SeedRegions do
  use Mix.Task
  alias BirdSong.Services.Ebird

  @requirements ["app.config", "app.start"]

  def run(opts) when is_list(opts) do
    opts
    |> get_data_folder()
    |> run()
  end

  def run("" <> parent_folder) do
    parent_folder
    |> get_all_regions()
    |> BirdSong.Region.seed()
  end

  def get_all_regions(parent_folder) do
    "world-country"
    |> parse_from_file(parent_folder)
    |> Enum.reduce([], &get_country_regions(&1, &2, parent_folder))
    |> List.flatten()
  end

  defp get_country_regions(%Ebird.Region{level: :country} = country, acc, parent_folder) do
    subnat_1 = parse_from_file(country.code <> "-subnational1", parent_folder)
    subnat_2 = parse_from_file(country.code <> "-subnational2", parent_folder)
    [country, subnat_1, subnat_2, acc]
  end

  defp parse_from_file(file_name, parent_folder) do
    parent_folder
    |> Path.join("regions/ebird")
    |> Path.join(file_name <> ".json")
    |> File.read!()
    |> Jason.decode!()
    |> case do
      [] -> []
      regions -> Enum.map(regions, &Ebird.Region.parse!/1)
    end
  end

  defp get_data_folder(["--folder=" <> folder]) do
    folder
  end

  defp get_data_folder([]) do
    "data"
  end
end
