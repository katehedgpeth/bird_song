defmodule BirdSongWeb.QuizLive.HTML do
  use Phoenix.HTML
  use Phoenix.LiveView
  alias Phoenix.HTML

  def page_title("" <> title) do
    HTML.Tag.content_tag(:h1, title, class: "mb-4")
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center flex-col w-full">
      <%= render_flash(assigns[:flash]) %>

      <.live_component
        module={@inner_template}
        id="inner_template"
        {Map.drop(assigns, [:inner_template])}
      />
    </div>
    """
  end

  ####################################################
  ####################################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################################

  defp render_flash(%{"error" => error}) do
    do_render_flash(error, :error)
  end

  defp render_flash(%{"info" => info}) do
    do_render_flash(info, :info)
  end

  defp render_flash(%{}) do
    ""
  end

  defp do_render_flash(error, type) do
    class =
      case type do
        :error -> "danger"
        :info -> "info"
      end

    HTML.Tag.content_tag(:p, error,
      class: "alert alert-#{class}",
      role: "alert",
      "phx-click": "lv:clear-flash",
      "phx-value-key": Atom.to_string(type)
    )
  end
end
