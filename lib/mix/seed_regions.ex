defmodule Mix.Tasks.BirdSong.SeedRegions do
  use Mix.Task
  alias BirdSong.Services.Ebird

  @requirements ["app.config", "app.start"]

  def run(opts) when is_list(opts) do
    opts
    |> parse_opts()
    |> run()
  end

  def run(%{folder: "" <> _, run_transaction?: _} = opts) do
    apply(
      BirdSong.Region,
      seed_function(opts),
      [get_all_regions(opts.folder)]
    )
  end

  defp seed_function(%{run_transaction?: true}), do: :seed!
  defp seed_function(%{run_transaction?: false}), do: :seed

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

  defp parse_opts(opts) do
    Enum.reduce(opts, %{folder: "data", run_transaction?: true}, &parse_opt/2)
  end

  defp parse_opt("--folder=" <> folder, opts) do
    Map.replace!(opts, :folder, folder)
  end

  defp parse_opt("--no-transaction", opts) do
    Map.replace!(opts, :run_transaction?, false)
  end
end
