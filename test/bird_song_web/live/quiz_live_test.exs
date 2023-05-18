defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz"
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]

  alias BirdSong.{
    Accounts,
    Bird
  }

  @moduletag load_view?: false

  setup [:seed_from_mock_taxonomy]

  setup tags do
    assert %{
             conn: conn,
             user: user,
             path_with_query: path
           } = Map.take(tags, [:conn, :user, :path_with_query])

    birds =
      Bird.get_many_by_common_name([
        "Carolina Wren",
        "Red-shouldered Hawk",
        "Northern Mockingbird"
      ])

    assert [%Bird{}, %Bird{}, %Bird{}] = birds

    assert %{quiz: quiz, user: user} =
             Accounts.update_current_quiz!(user.id, %{region_code: "US-NC", birds: birds})

    assert {:ok, view, _html} = live(conn, path)

    {:ok, birds: birds, quiz: quiz, user: user, view: view}
  end

  test "connected mount", %{view: view} do
    assert has_element?(view, "button", "Skip to next bird")
  end
end
