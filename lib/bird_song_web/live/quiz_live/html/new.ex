defmodule BirdSongWeb.QuizLive.HTML.NewQuiz do
  use Phoenix.LiveComponent
  alias BirdSongWeb.QuizLive

  def render(assigns) do
    ~H"""
    <%= QuizLive.HTML.page_title("How well do you know your bird songs?") %>
    <%= QuizLive.HTML.Filters.render(assigns) %>
    """
  end
end
