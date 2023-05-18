defmodule BirdSong.Quiz.Answer do
  use Ecto.Schema
  import Ecto.Changeset

  alias BirdSong.{
    Bird,
    Quiz
  }

  schema "quiz_answers" do
    field :correct?, :boolean, default: false
    belongs_to :quiz, Quiz
    belongs_to :bird, Bird

    timestamps()
  end

  @doc false
  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [:correct?])
    |> validate_required([:correct?])
  end
end
