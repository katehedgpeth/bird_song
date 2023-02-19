defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.LiveCase

  test "connected mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/quiz")
    assert html =~ "Hello world!"
  end
end
