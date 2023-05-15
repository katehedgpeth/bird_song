defmodule BirdSongWeb.Components.Collapse do
  use Phoenix.LiveComponent

  defstruct [:title, :body, :state, :element, phx_value: [], icon_type: :plus]

  def render(%{assigns: %__MODULE__{} = assigns}) do
    ~H"""
      <div>
        <.collapse state={@state} element={@element} phx_value={@phx_value} icon_type={@icon_type}>
          <:title> <%= @title %> </:title>
          <:body> <%= @body %> </:body>
        </.collapse>
      </div>
    """
  end

  defp collapse(%{} = assigns) do
    ~H"""
    <div>
      <div class="flex justify-between justify-items-center" {[
        phx: [
          click: "toggle_visibility",
          value: [ {:element, @element} | @phx_value ]
        ]
      ]}>
        <div class="flex-none w-4">
          <%= collapse_icon(@state, @icon_type) %>
        </div>
        <div class="grow">
          <%= render_slot(@title) %>
        </div>
      </div>
      <%= if @state === :shown do %>
        <div>
          <%= render_slot(@body) %>
        </div>
      <% end %>
    </div>
    """
  end

  defp collapse_icon(:hidden, :plus), do: "+"
  defp collapse_icon(:shown, :plus), do: "-"
  defp collapse_icon(:hidden, :caret), do: caret_right(%{})
  defp collapse_icon(:shown, :caret), do: caret_down(%{})

  defp caret_down(assigns) do
    ~H"""
    <svg
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:cc="http://creativecommons.org/ns#"
      xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      xmlns:svg="http://www.w3.org/2000/svg"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 -256 1792 1792"
      width="100%"
      height="100%"
    >
      <g transform="matrix(1,0,0,-1,402.44068,1239.8644)">
        <path
          d={[
            "m 1024,832",
            "q 0,-26 -19,-45",
            "L 557,339",
            "q -19,-19 -45,-19 -26,0 -45,19",
            "L 19,787",
            "q -19,19 -19,45 0,26 19,45 19,19 45,19",
            "h 896 q 26,0 45,-19 19,-19 19,-45",
            "z"
          ]}
          style="fill:currentColor"
        />
      </g>
    </svg>
    """
  end

  defp caret_right(assigns) do
    ~H"""
    <svg
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:cc="http://creativecommons.org/ns#"
      xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      xmlns:svg="http://www.w3.org/2000/svg"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:sodipodi="http://sodipodi.sourceforge.net/DTD/sodipodi-0.dtd"
      xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
      viewBox="0 -256 1792 1792"
      version="1.1" inkscape:version="0.48.3.1 r9886"
      width="100%"
      height="100%"
    >
      <g transform="matrix(1,0,0,-1,584.67797,1262.6441)">
        <path
          d={[
            "m 576,640",
            "q 0,-26 -19,-45",
            "L 109,147",
            "Q 90,128 64,128 38,128 19,147 0,166 0,192 v 896",
            "q 0,26 19,45 19,19 45,19 26,0 45,-19",
            "L 557,685",
            "q 19,-19 19,-45",
            "z",
          ]}
          style="fill:currentColor"
        />
      </g>
    </svg>

    """
  end
end
