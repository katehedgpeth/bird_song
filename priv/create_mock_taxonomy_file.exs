alias BirdSong.{TestHelpers, Services.Ebird.Taxonomy}

taxonomy =
  Taxonomy.read_data_file()
  |> Enum.map(fn data -> {data["speciesCode"], data} end)
  |> Enum.into(%{})

"mock_taxonomy"
|> TestHelpers.mock_file_path()
|> File.write!(
  "data/forsyth_species_codes.json"
  |> Taxonomy.read_data_file()
  |> Enum.take(15)
  |> Enum.concat(["reshaw"])
  |> Enum.map(fn code -> Map.fetch!(taxonomy, code) end)
  |> Jason.encode!()
)
