defmodule BirdSong.Quiz do
  use Ecto.Schema
  import Ecto.Changeset

  # region is temporarily hard-coded; future version will take user input
  @default_region "US-NC-067"

  schema "quizzes" do
    field :birds, {:array, :string}, default: []
    field :correct_answers, :integer, default: 0
    field :incorrect_answers, :integer, default: 0
    field :quiz_length, :integer, default: 10
    field :region, :string, default: "US-NC-067"

    # timestamps()
  end

  @doc false
  def changeset(quiz, attrs) do
    quiz
    |> cast(attrs, [:correct_answers, :incorrect_answers, :region, :quiz_length, :birds])
    |> validate_required([:region, :quiz_length])
  end

  def default_changeset() do
    changeset(%__MODULE__{region: @default_region}, %{})
  end

  def add_bird(%__MODULE__{} = quiz, "" <> bird_id) do
    Map.update!(quiz, :birds, &do_add_bird(&1, bird_id))
  end

  defp do_add_bird(birds, bird_id) do
    List.insert_at(
      birds,
      birds
      |> length()
      |> Range.new(0)
      |> Enum.random(),
      bird_id
    )
  end
end
