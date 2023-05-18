defmodule BirdSong.Quiz.BadUserError do
  use BirdSong.CustomError, [:quiz, :user]

  def message_text(%__MODULE__{quiz: quiz, user: user}) do
    """
    Quiz does not belong to user!
    quiz.user_id: #{quiz.user_id}
    user_id: #{user.id}
    """
  end
end

defmodule BirdSong.Quiz do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias BirdSong.Quiz.BadUserError

  alias BirdSong.{
    Accounts.User,
    Bird,
    Quiz.Answer,
    Repo
  }

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
    field :use_recent_observations?, :boolean
    belongs_to :user, User
    has_many :answers, Answer
    many_to_many :birds, Bird, join_through: "birds_quizzes", unique: true

    timestamps()
  end

  def multi_insert_quiz(%{user: user}, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:quiz, changeset(user, attrs))
  end

  def changeset(%User{} = user, %{} = attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :correct_answers,
      :incorrect_answers,
      :quiz_length,
      :region_code
    ])
    |> put_assoc(:birds, attrs[:birds])
    |> put_assoc(:user, user)
    |> validate_required([:region_code, :quiz_length, :birds, :user])
    |> validate_length(:birds, min: 1)
  end

  def default_changeset() do
    change(%__MODULE__{})
  end

  def get_current_for_user!(%User{current_quiz_id: nil}) do
    nil
  end

  def get_current_for_user!(%User{id: user_id, current_quiz_id: quiz_id} = user)
      when is_integer(quiz_id) do
    case BirdSong.Repo.get!(__MODULE__, quiz_id) do
      %__MODULE__{user_id: ^user_id} = quiz ->
        Repo.preload(quiz, birds: [:family])

      %__MODULE__{} = quiz ->
        raise BadUserError.exception(quiz: quiz, user: user)
    end
  end

  def get_all_for_user(%User{id: user_id}) do
    BirdSong.Repo.all(
      from q in __MODULE__,
        where: q.user_id == ^user_id,
        preload: [:user]
    )
  end
end
