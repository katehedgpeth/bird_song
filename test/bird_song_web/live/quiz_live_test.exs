defmodule BirdSongWeb.QuizLiveTest do
  use BirdSongWeb.LiveCase
  use BirdSong.MockApiCase

  @moduletag service: :ebird

  @path "/quiz"

  @data "test/mock_data/recent_observations.json"
        |> Path.relative_to_cwd()
        |> File.read!()

  test "connected mount", %{conn: conn} do
    assert {:ok, view, html} = live(conn, @path)
    assert html =~ "How well do you know your bird songs?"
    assert view |> form("#settings") |> render_submit() =~ "What bird do you hear?"
  end

  @tag :skip
  describe "user can enter a location" do
    test "by typing", %{conn: conn} do
      assert {:ok, view, html} = live(conn, @path)
      assert html =~ "Winston Salem, NC"

      assert view
             |> form("#settings", quiz: %{region: "Greensboro, NC"})
             |> render_submit() =~ "Greensboro, NC"
    end

    test "by using their browser location" do
    end

    test "and be shown an error when the location is not recognized" do
    end
  end

  describe("user can specify the max number of questions to be asked") do
    test "by typing", %{conn: conn} do
      assert {:ok, view, html} = live(conn, @path)
      assert html =~ "Number of Questions"
      refute html =~ "1000"

      assert view
             |> form("#settings", quiz: %{quiz_length: 1000})
             |> render_submit() =~ "What bird do you hear?"
    end
  end

  def ebird_success_response(conn) do
    Plug.Conn.resp(conn, 200, @data)
  end
end
