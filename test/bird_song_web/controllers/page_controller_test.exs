defmodule BirdSongWeb.PageControllerTest do
  use BirdSongWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Start a new quiz"
  end
end
