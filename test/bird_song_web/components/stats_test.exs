defmodule BirdSongWeb.Components.ViewUnderTest do
  use Phoenix.LiveView

  alias BirdSongWeb.Components

  on_mount(BirdSongWeb.QuizLive.User)
  on_mount({Components.Stats, :get})

  def render(assigns) do
    ~H"""
      <.live_component module={Components.Stats} id="stats" {assigns} />
    """
  end

  def handle_call(:assigns, _from, socket) do
    {:reply, socket.assigns, socket}
  end
end

defmodule BirdSongWeb.Components.StatsTest do
  use BirdSongWeb.LiveCase

  import BirdSong.TestSetup

  alias BirdSong.{
    Bird
  }

  @moduletag pct_correct: 80

  setup [
    :seed_from_mock_taxonomy,
    :register_and_log_in_user,
    :generate_answers
  ]

  describe "render" do
    setup %{conn: conn} do
      assert {:ok, view, html} = live_isolated(conn, BirdSongWeb.Components.ViewUnderTest, [])
      {:ok, view: view, html: html}
    end

    test "shows stats", %{html: html, answers: answers} do
      assert BirdSong.Repo.all(Bird) |> length() === 5
      assert length(answers) === 4
      assert MapSet.new(answers, & &1.correct?) === MapSet.new([true, false])
      assert html =~ "3 / 4\n  (75.0%)"
    end
  end

  ############################################################
  ############################################################
  ##
  ##  SETUP METHODS
  ##
  ############################################################

  defp generate_answers(tags) do
    %{answers: BirdSong.QuizFixtures.generate_answers(tags, 3)}
  end
end
