defmodule BirdSongWeb.QuizLive.HTML.Filters do
  use Phoenix.LiveComponent
  alias Phoenix.HTML
  alias BirdSongWeb.Components.{ButtonGroup, GroupButton}

  def render(assigns) do
    ~H"""
    <.form
      let={q}
      for={@filters}
      id="settings"
      phx-change="validate"
      phx-submit="start"
      class="w-full md:w-1/2 flex flex-col space-y-4"
    >
      <div>
        <%=
          HTML.Form.label q, :region, HTML.Tag.content_tag(:span, [
            "Region",
            HTML.Tag.content_tag(:span, " (can be city, state, or country)", class: "italic")
          ])
        %>
        <div class="flex">
          <%= HTML.Form.text_input q, :region, "phx-debounce": 3, class: @text_input_class, id: "region-input" %>
          <%= HTML.Tag.content_tag(:button, "Set region", type: :button, "phx-click": "set_region", class: "btn", id: "region-btn") %>
        </div>
      </div>
      <div>
        <%= show_species_filter_buttons(assigns) %>
      </div>

      <%= HTML.Form.submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
    """
  end

  ####################################################
  ####################################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################################

  defp show_species_filter_buttons(%{birds: []}) do
    ""
  end

  defp show_species_filter_buttons(%{species_categories: categories}) do
    HTML.Tag.content_tag(
      :div,
      [
        HTML.Tag.content_tag(:h3, "Limit to these groups (optional):"),
        species_filter_buttons(categories)
      ],
      id: "species-filter"
    )
  end

  defp species_filter_button({category_name, selected?}),
    do: %GroupButton{
      color: "accent",
      selected?: selected?,
      text: category_name,
      value: category_name
    }

  defp species_filter_buttons(categories) do
    categories
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&species_filter_button/1)
    |> ButtonGroup.render()
  end
end
