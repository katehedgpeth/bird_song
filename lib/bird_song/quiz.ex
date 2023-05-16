defmodule BirdSong.Quiz do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2, last: 2]

  @type t() :: %__MODULE__{
          birds: [String.t()],
          correct_answers: integer(),
          incorrect_answers: integer(),
          quiz_length: integer(),
          region_code: String.t(),
          use_recent_observations?: boolean()
        }

  schema "quizzes" do
    field :correct_answers, :integer, default: 0
    field :incorrect_answers, :integer, default: 0
    field :quiz_length, :integer, default: 10
    field :region_code, :string
    field :session_id, :string
    field :use_recent_observations?, :boolean
    many_to_many :birds, BirdSong.Bird, join_through: "birds_quizzes"

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = quiz, %{} = changes) do
    quiz
    |> cast(changes, [
      :correct_answers,
      :incorrect_answers,
      :quiz_length,
      :region_code
    ])
    |> cast_assoc(:birds, required: true)
    |> validate_required([:region_code, :quiz_length, :session_id])
  end

  def create!(filters) do
    filters
    |> __struct__()
    |> changeset(%{})
    |> BirdSong.Repo.insert!()
  end

  def default_changeset() do
    change(%__MODULE__{})
  end

  def get_latest_by_session_id("" <> session_id) do
    from(q in __MODULE__, where: q.session_id == ^session_id, preload: [birds: [:family, :order]])
    |> last(:inserted_at)
    |> BirdSong.Repo.one()
  end

  def get_all_by_session_id("" <> session_id) do
    BirdSong.Repo.all(
      from q in __MODULE__,
        where: q.session_id == ^session_id
    )
  end
end
