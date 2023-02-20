defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.LiveCase
  use BirdSong.MockApiCase

  @moduletag service: :ebird

  @data "test/mock_data/recent_observations.json"
        |> Path.relative_to_cwd()
        |> File.read!()

  @tag expect_once: &__MODULE__.ebird_success_response/1
  test "connected mount", %{conn: conn} do
    assert {:ok, view, html} = live(conn, "/quiz")
    assert html =~ "Hello world!"
    assert_push_event(view, :recent_observations, %{data: data})
    assert Enum.count(data) === 104
  end

  def ebird_success_response(conn) do
    Plug.Conn.resp(conn, 200, @data)
  end
end
