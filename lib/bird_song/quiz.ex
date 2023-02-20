defmodule BirdSong.Quiz do
  use Ecto.Schema
  import Ecto.Changeset

  schema "quizzes" do
    field :birds, {:array, :string}
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
end
