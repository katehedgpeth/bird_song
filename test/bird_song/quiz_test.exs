defmodule BirdSong.QuizTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup

  alias Ecto.Changeset

  alias BirdSong.{
    Bird,
    Quiz
  }

  setup [:seed_from_mock_taxonomy]

  setup do
    {:ok,
     birds:
       Bird.get_many_by_common_name([
         "Eastern Bluebird",
         "Carolina Wren",
         "Common Grackle"
       ])}
  end

  test "changeset returns a changeset without errors when data is valid", %{birds: birds} do
    required = [:region_code, :quiz_length, :session_id, :birds]

    assert %Changeset{
             data: %Quiz{},
             errors: errors,
             params: %{},
             required: ^required,
             valid?: false
           } = Quiz.changeset(%Quiz{}, %{})

    not_blank = {"can't be blank", validation: :required}
    assert errors === [region_code: not_blank, session_id: not_blank, birds: not_blank]

    assert %Changeset{
             changes: %{region_code: "US"},
             data: data,
             errors: [session_id: ^not_blank, birds: ^not_blank],
             params: params,
             required: ^required,
             valid?: false
           } = Quiz.changeset(%Quiz{}, %{region_code: "US"})

    assert params === %{"region_code" => "US"}
    assert %Quiz{} = data

    session_id = Ecto.UUID.generate()

    assert %Changeset{
             changes: %{
               region_code: "US-NC"
             },
             data: %Quiz{},
             errors: [],
             params: %{"region_code" => "US-NC"},
             required: ^required,
             valid?: true
           } =
             Quiz.changeset(
               %Quiz{
                 region_code: "US",
                 birds: birds,
                 session_id: session_id
               },
               %{
                 region_code: "US-NC"
               }
             )
  end

  describe "create!/1" do
    test "inserts to DB when data is valid", %{birds: birds} do
      assert length(birds) === 3

      assert %Quiz{id: id} =
               Quiz.create!(
                 region_code: "US-NC-067",
                 birds: birds,
                 session_id: Ecto.UUID.generate()
               )

      assert is_integer(id)
    end
  end

  describe "get_*_by_session_id/1" do
    setup tags do
      assert %{birds: birds} = tags
      assert [bluebird, wren, grackle] = birds

      session_id = Ecto.UUID.generate()

      two_minutes_ago =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(-2, :minute)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)

      first =
        Quiz.create!(
          region_code: "US-NC-067",
          birds: [bluebird, wren],
          session_id: session_id,
          inserted_at: two_minutes_ago,
          updated_at: two_minutes_ago
        )

      second =
        Quiz.create!(
          region_code: "US-NC-067",
          birds: [wren, grackle],
          session_id: session_id
        )

      {:ok, created: [first, second], session_id: session_id}
    end

    test "get_all_by_session_id/1 returns a list of quizzes when they exist", %{
      created: [first, second],
      session_id: session_id
    } do
      assert [first_result, second_result] = Quiz.get_all_by_session_id(session_id)
      assert first.id === first_result.id
      assert second.id === second_result.id
    end

    test "get_latest_by_session_id/1 returns the most recently created quiz for a session", %{
      created: [first, second],
      session_id: session_id
    } do
      assert NaiveDateTime.compare(first.inserted_at, second.inserted_at) === :lt
      assert %Quiz{id: id} = Quiz.get_latest_by_session_id(session_id)
      assert id === second.id
    end

    test "get_latest_by_session_id/1 returns nil if there are no quizzes for the session", %{} do
      session_id = Ecto.UUID.generate()
      assert Quiz.get_latest_by_session_id(session_id) === nil
    end
  end
end
