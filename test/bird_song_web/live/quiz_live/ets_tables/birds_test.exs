defmodule BirdSongWeb.QuizLive.EtsTables.BirdsTest do
  use ExUnit.Case
  alias Phoenix.LiveView.Socket
  alias BirdSongWeb.QuizLive
  alias QuizLive.EtsTables.Birds

  test "&update_bird_count/1 updates the number of birds in the table", %{} do
    {:ok, socket} = QuizLive.mount(%{}, %{}, %Socket{})
    assert Birds.get_bird_count(socket) === 0
    assert get_bird_count(socket) === 0
  end

  def get_bird_count(%Socket{assigns: %{bird_count: count}}), do: count
end
