defmodule BirdSongWeb.QuizLive.NewTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz/new", async: true
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
    test "saves filters to database and redirects to /quiz when receives a :start message", %{
      view: view
    } do
      birds = Bird.get_many_by_common_name(["Eastern Bluebird", "Red-shouldered Hawk"])
      assert [_, _] = birds
      socket = GenServer.call(view.pid, :socket)

      assert Quiz.get_all_by_session_id(socket.assigns.session_id) === []

      BirdSong.PubSub.broadcast(
        socket,
        {:start, birds: birds, region_code: "US-NC-067"}
      )

      assert_redirect(view, "/quiz")

      assert [%Quiz{}] = Quiz.get_all_by_session_id(socket.assigns.session_id)
    end
  end
end
