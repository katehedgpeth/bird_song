defmodule BirdSongWeb.QuizLive.HTML do
  use Phoenix.HTML
  use Phoenix.LiveView
  alias Phoenix.HTML

  def page_title("" <> title) do
    HTML.Tag.content_tag(:h1, title, class: "mb-4")
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center flex-col">
      <%= @inner_template.(assigns) %>
    </div>
    """
  end

  ####################################################
  ####################################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################################
end
