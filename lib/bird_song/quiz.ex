defmodule BirdSong.Quiz do
  use Ecto.Schema
  import Ecto.Changeset
  alias BirdSong.Services.Ebird.Region
  alias Ecto.InvalidChangesetError
  alias Ecto.Changeset

  @type t() :: %__MODULE__{
          birds: [String.t()],
          correct_answers: integer(),
          incorrect_answers: integer(),
          quiz_length: integer(),
          region: String.t() | nil
        }

  schema "quizzes" do
    field :birds, {:array, :string}, default: []
    field :correct_answers, :integer, default: 0
    field :incorrect_answers, :integer, default: 0
    field :quiz_length, :integer, default: 10
    field :region, :string
    # , default: "US-NC-067"

    # timestamps()
  end

  def apply_valid_changes(%Changeset{
        valid?: true,
        changes: %{} = changes,
        data: %__MODULE__{} = data
      }) do
    Map.merge(data, changes)
  end

  def apply_valid_changes(%Changeset{valid?: false} = changeset) do
    changeset
  end

  def apply_valid_changes!(%Changeset{} = changeset) do
    case apply_valid_changes(changeset) do
      %__MODULE__{} = quiz -> quiz
      %Changeset{valid?: false} -> raise InvalidChangesetError.exception(changeset: changeset)
    end
  end

  @doc false
  def changeset(%__MODULE__{} = quiz, %{} = changes) do
    quiz
    |> cast(changes, [:correct_answers, :incorrect_answers, :region, :quiz_length, :birds])
    |> validate_required([:region, :quiz_length])
    |> validate_change(:region, &validate_region/2)
  end

  def default_changeset() do
    changeset(%__MODULE__{}, %{})
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

  @spec get_region(t()) ::
          {:error, :not_set} | {:ok, Region.t()}
  def get_region(%__MODULE__{region: "" <> region}) do
    {:ok, Region.from_code!(region)}
  end

  def get_region(%__MODULE__{region: nil}) do
    {:error, :not_set}
  end

  def get_region(%Changeset{valid?: false, data: data}), do: get_region(data)

  def get_region(%Changeset{} = changeset) do
    changeset
    |> apply_valid_changes!()
    |> get_region()
  end

  defp validate_region(:region, "" <> region_code) do
    region_code
    |> Region.from_code()
    |> case do
      {:ok, %Region{}} -> []
      {:error, %Region.NotFoundError{}} -> [region: "unknown: #{region_code}"]
    end
  end
end
