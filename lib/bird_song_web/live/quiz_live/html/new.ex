defmodule BirdSongWeb.QuizLive.HTML.NewQuiz do
  use Phoenix.LiveComponent

  alias BirdSongWeb.{
    Components.Filters,
    QuizLive
  }

  def render(assigns) do
    ~H"""
      <div class="w-full md:w-3/4">
        <%= QuizLive.HTML.page_title("How well do you know your bird songs?") %>
        <%= Filters.render_filters(assigns) %>
      </div>
    """
  end
end
