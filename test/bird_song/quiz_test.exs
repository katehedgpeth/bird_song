defmodule BirdSong.QuizTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup

  alias Ecto.Changeset
  alias BirdSong.AccountsFixtures

  alias BirdSong.{
    Accounts,
    Bird,
    Quiz
  }

  @cant_be_blank_error {"can't be blank", validation: :required}

  setup [:seed_from_mock_taxonomy]

  setup tags do
    {:ok,
     user: AccountsFixtures.user_fixture(),
     birds:
       case tags do
         %{seed_birds?: false} ->
           []

         %{} ->
           Bird.get_many_by_common_name([
             "Eastern Bluebird",
             "Carolina Wren",
             "Common Grackle"
           ])
       end}
  end

  describe "changeset/2" do
    test "returns a changeset with errors when region_code is missing", %{
      birds: birds,
      user: user
    } do
      changeset = Quiz.changeset(user, %{birds: birds})
      assert %Changeset{} = changeset

      assert changeset.required === [:region_code, :quiz_length, :birds, :user]
      assert %{"birds" => ^birds} = changeset.params
      assert changeset.errors === [region_code: @cant_be_blank_error]
    end

    test "returns a changeset with errors when birds is missing", %{user: user} do
      changeset = Quiz.changeset(user, %{region_code: "US"})

      assert %Changeset{} = changeset
      assert changeset.params === %{"region_code" => "US"}

      assert changeset.errors === [birds: {"is invalid", type: {:array, :map}}]
      assert changeset.data === %Quiz{}
    end

    test "returns a changeset with errors when birds is an empty array", %{user: user} do
      changeset = Quiz.changeset(user, %{region_code: "US-NC", birds: []})

      assert %Changeset{} = changeset

      refute changeset.valid?

      assert %{birds: [], region_code: "US-NC", user: %Changeset{data: %Accounts.User{}}} =
               changeset.changes

      assert changeset.errors === [
               birds:
                 {"should have at least %{count} item(s)",
                  count: 1, validation: :length, kind: :min, type: :list}
             ]

      assert changeset.params === %{"birds" => [], "region_code" => "US-NC"}
    end

    test "returns a valid changeset when all data is valid", %{user: user, birds: birds} do
      changeset = Quiz.changeset(user, %{region_code: "US-NC", birds: birds})
      assert %Changeset{} = changeset
      assert changeset.valid?
      assert changeset.errors === []
    end
  end

  describe "get_*_by_user_id/1" do
    setup tags do
      assert %{birds: birds} = tags
      assert [bluebird, wren, grackle] = birds

      two_minutes_ago =
        DateTime.now!("Etc/UTC")
        |> DateTime.add(-2, :minute)
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)

      {:ok,
       params: [
         %{
           region_code: "US-NC-067",
           birds: [bluebird, wren],
           inserted_at: two_minutes_ago,
           updated_at: two_minutes_ago
         },
         %{
           region_code: "US-NC-067",
           birds: [wren, grackle]
         }
       ]}
    end

    test "get_all_for_user/1 returns a list of quizzes when they exist", tags do
      assert {:ok, %{quiz_1: first, quiz_2: second}} = insert_multiple(tags)

      assert [first_result, second_result] = Quiz.get_all_for_user(tags.user)
      assert first.id === first_result.id
      assert second.id === second_result.id
    end

    test "get_current_for_user/1 uses the user's current_quiz_id value", %{
      params: [_first, second],
      user: user
    } do
      assert %{quiz: quiz, user: user} = Accounts.update_current_quiz!(user, second)
      assert user.current_quiz_id === quiz.id
      assert %Quiz{id: id} = Quiz.get_current_for_user!(user)
      assert id === quiz.id
    end

    test "get_latest_by_user_id/1 returns nil if a current quiz has not been assigned", %{
      user: user
    } do
      assert user.current_quiz_id === nil
      assert Quiz.get_current_for_user!(user) === nil
    end
  end

  defp insert_multiple(%{params: params, user: user}) do
    params
    |> Enum.with_index(1)
    |> Enum.reduce(Ecto.Multi.new(), &do_insert_multiple(&1, user, &2))
    |> BirdSong.Repo.transaction()
  end

  defp do_insert_multiple({params, index}, user, multi) do
    Ecto.Multi.insert(multi, :"quiz_#{index}", Quiz.changeset(user, params))
  end
end
