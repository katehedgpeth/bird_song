defmodule BirdSong.BirdFixtures.EmptyDbError do
  use BirdSong.CustomError, [:message]

  def message_text(%__MODULE__{}) do
    "No birds in database!"
  end
end

defmodule BirdSong.BirdFixtures do
  alias BirdSong.{
    Bird
  }

  @mock_taxonomy "test/mock_data/mock_taxonomy.json"
  @default_count 5

  @doc """
  Gets a random bird from the database.

  If the database has not been seeded, it will be seeded with `BirdFixtures.seed_db()`.
  """
  def random(repo \\ BirdSong.Repo) do
    repo
    |> all_birds_in_db()
    |> Enum.shuffle()
    |> List.first()
  end

  @doc """
  Generates a random list of birds.

  If the database has not been seeded, it will be seeded with
    `BirdFixtures.seed_db(%{count: count, randomize_order?: true})`
  """
  def random_list(count \\ @default_count) do
    all_birds_in_db()
    |> Enum.shuffle()
    |> Enum.take(count)
  end

  defp all_birds_in_db(repo \\ BirdSong.Repo) do
    case repo.all(Bird) do
      [] ->
        raise __MODULE__.EmptyDbError.exception([])

      [%Bird{} | _] = all_birds ->
        all_birds
    end
  end
end
