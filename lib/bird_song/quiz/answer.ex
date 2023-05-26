defmodule BirdSong.Quiz.Answer do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Ecto.Changeset

  alias BirdSong.{
    Accounts.User,
    Bird,
    Quiz,
    Repo
  }

  schema "quiz_answers" do
    field :correct?, :boolean, default: false
    belongs_to :quiz, Quiz
    belongs_to :correct_bird, Bird
    belongs_to :submitted_bird, Bird
    has_one :user, through: [:quiz, :user]

    timestamps()
  end

  @doc false
  def changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:correct?, :inserted_at, :updated_at])
    |> put_assoc(:quiz, attrs[:quiz])
    |> put_assoc(:submitted_bird, attrs[:submitted_bird])
    |> put_assoc(:correct_bird, attrs[:correct_bird])
    |> Ecto.Changeset.prepare_changes(&set_correct/1)
    |> validate_required([:correct?, :correct_bird, :quiz, :submitted_bird])
  end

  def submit!(%{} = params) do
    params
    |> changeset()
    |> Repo.insert!()
  end

  def get_for_quiz(quiz_id) when is_integer(quiz_id) do
    Repo.all(
      from __MODULE__,
        where: [quiz_id: ^quiz_id]
    )
  end

  def get_all_for_user(%{user: %User{} = user}) do
    Ecto.Multi.new()
    |> Ecto.Multi.all(:all_answers_for_user, Ecto.assoc(user, :answers))
  end

  def inserted_on_or_after?(%__MODULE__{inserted_at: date}, must_be_on_or_after) do
    case Date.compare(date, must_be_on_or_after) do
      :lt -> false
      :eq -> true
      :gt -> true
    end
  end

  def query_created_since_ago(amount, unit) do
    from a in __MODULE__, where: a.inserted_at < ago(^amount, ^unit)
  end

  def query_created_after_ago(amount, unit) do
    from(a in __MODULE__, where: a.inserted_at > ago(^amount, ^unit))
  end

  defp set_correct(
         %Changeset{
           changes: %{
             correct_bird: %Changeset{data: %Bird{id: id}},
             submitted_bird: %Changeset{data: %Bird{id: submitted_id}}
           }
         } = changeset
       )
       when id !== nil and submitted_id !== nil do
    Changeset.put_change(
      changeset,
      :correct?,
      id === submitted_id
    )
  end
end
