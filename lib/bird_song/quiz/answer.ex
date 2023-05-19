defmodule BirdSong.Quiz.Answer do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias BirdSong.{
    Bird,
    Quiz,
    Repo
  }

  schema "quiz_answers" do
    field :correct?, :boolean, default: false
    belongs_to :quiz, Quiz
    belongs_to :correct_bird, Bird
    belongs_to :submitted_bird, Bird

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:correct?])
    |> put_assoc(:quiz, attrs[:quiz])
    |> put_assoc(:submitted_bird, attrs[:submitted_bird])
    |> put_assoc(:correct_bird, attrs[:correct_bird])
    |> validate_required([:correct?, :correct_bird, :quiz, :submitted_bird])
  end

  def submit!(%{} = params) do
    params
    |> Map.put(:correct?, params.correct_bird.id === params.submitted_bird.id)
    |> changeset()
    |> Repo.insert!()
  end

  def get_for_quiz(quiz_id) when is_integer(quiz_id) do
    Repo.all(
      from __MODULE__,
        where: [quiz_id: ^quiz_id]
    )
  end
end
