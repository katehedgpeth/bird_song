require Logger
alias BirdSong.{TestHelpers, Services.Ebird.Taxonomy, Services.ThrottledCache}

if Mix.env() !== :test do
  raise "This task should only be run on MIX_ENV=test!!!"
end

Mix.Task.run("ecto.drop")
Mix.Task.run("ecto.create")
Mix.Task.run("ecto.migrate")

Logger.configure(level: :debug)

mock_taxonomy_file_name = "taxonomy"
one_second = 1_000

full_taxonomy =
  Taxonomy.read_data_file()
  |> Enum.map(fn data -> {data["speciesCode"], data} end)
  |> Enum.into(%{})

forsyth_codes = Taxonomy.read_data_file("data/forsyth_species_codes.json")

mock_taxonomy_file_name
|> TestHelpers.mock_file_path()
|> File.write!(
  forsyth_codes
  |> Enum.map(&Map.fetch!(full_taxonomy, &1))
  |> Jason.encode!()
)

# Application.put_env(:bird_song, :write_to_disk?, true)
# TestHelpers.update_env(ThrottledCache, :backlog_timeout_ms, :infinity)
# TestHelpers.update_env(ThrottledCache, :throttle_ms, 2 * one_second)
# TestHelpers.update_env(:xeno_canto, :api_response_timeout_ms, :infinity)
# TestHelpers.update_env(BirdSong.Repo, :pool, nil)

mock_taxonomy_file_name
|> TestHelpers.mock_file_path()
|> Taxonomy.read_data_file()
|> Taxonomy.seed()
|> Enum.map(&Task.await/1)
