defmodule BirdSongWeb.QuizLive.HTML.NewQuiz do
  use Phoenix.LiveComponent

  alias BirdSongWeb.{
    Components.Filters,
    QuizLive
  }

  def render(assigns) do
    ~H"""
      <%= QuizLive.HTML.page_title("How well do you know your bird songs?") %>
      <.live_component module={Filters} id="filters" {assigns} />
    """
  end
end
