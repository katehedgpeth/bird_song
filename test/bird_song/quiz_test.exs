defmodule BirdSong.QuizTest do
  use ExUnit.Case
  alias BirdSong.Quiz
  alias Ecto.Changeset

  @default_changeset Quiz.default_changeset()

  test "changeset returns a changeset without errors when data is valid" do
    assert Quiz.changeset(%Quiz{}, %{}) === %Changeset{
             data: %Quiz{},
             errors: [region: {"can't be blank", validation: :required}],
             params: %{},
             required: [:region, :quiz_length],
             types: @default_changeset.types,
             valid?: false
           }

    assert Quiz.changeset(%Quiz{}, %{region: "US"}) === %Changeset{
             changes: %{region: "US"},
             data: %Quiz{},
             errors: [],
             params: %{"region" => "US"},
             required: [:region, :quiz_length],
             types: @default_changeset.types,
             valid?: true
           }

    assert Quiz.changeset(%Quiz{region: "US"}, %{region: "US-NC"}) === %Changeset{
             changes: %{region: "US-NC"},
             data: %Quiz{region: "US"},
             errors: [],
             params: %{"region" => "US-NC"},
             required: [:region, :quiz_length],
             types: @default_changeset.types,
             valid?: true
           }
  end

  test "apply_valid_changes/1 returns a Quiz struct when data is valid" do
    assert %Quiz{}
           |> Quiz.changeset(%{region: "US-NC"})
           |> Quiz.apply_valid_changes() === %Quiz{region: "US-NC"}
  end
end
