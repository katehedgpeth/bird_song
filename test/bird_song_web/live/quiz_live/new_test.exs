defmodule BirdSongWeb.QuizLive.NewTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz/new"
  import BirdSong.TestSetup

  alias BirdSong.{
    Bird,
    Quiz
  }

  @moduletag :capture_log

  setup [
    :seed_from_mock_taxonomy
  ]

  describe "connected mount - success scenarios" do
    @tag login?: false
    test "requires login", %{conn: conn, path_with_query: path_with_query} do
      assert {:error, {:redirect, %{to: "/users/log_in"}}} =
               Phoenix.LiveViewTest.live(conn, path_with_query)
    end

    test "saves filters to database and redirects to /quiz when receives a :start message", %{
      view: view,
      user: user
    } do
      birds = Bird.get_many_by_common_name(["Eastern Bluebird", "Red-shouldered Hawk"])
      assert [_, _] = birds
      socket = GenServer.call(view.pid, :socket)

      assert Quiz.get_all_for_user(user) === []

      BirdSong.PubSub.broadcast(
        socket,
        {:start, birds: birds, region_code: "US-NC-067"}
      )

      assert_redirect(view, "/quiz")

      assert [quiz] = Quiz.get_all_for_user(user)
      assert %Quiz{} = quiz
      assert quiz.user.id === user.id
    end
  end
end
