defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.LiveCase
  use BirdSong.MockApiCase

  @moduletag service: :ebird

  @species_list ["QUIZ_LIVE_TEST"]

  @tag expect_once: &__MODULE__.ebird_success_response/1
  test "connected mount", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/quiz")
    assert html =~ "Hello world!"
    assert_push_event(view, :bird_list, %{data: @species_list})
  end

  def ebird_success_response(conn) do
    Plug.Conn.resp(conn, 200, Jason.encode!(@species_list))
  end
end
