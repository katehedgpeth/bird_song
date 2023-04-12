defmodule BirdSongWeb.Components.GroupButton do
  @enforce_keys [:text, :value]
  defstruct [:color, :text, :value, selected?: false]

  @type t() :: %__MODULE__{
          color: String.t(),
          selected?: boolean(),
          text: String.t(),
          value: String.t()
        }
end

defmodule BirdSongWeb.Components.ButtonGroup do
  use Phoenix.HTML
  alias Phoenix.HTML.Tag
  alias BirdSongWeb.Components.GroupButton

  def render([%GroupButton{} | _] = buttons) do
    Tag.content_tag(
      :div,
      Enum.map(buttons, &group_button/1),
      class: "flex flex-wrap gap-2"
    )
  end

  defp group_button(%GroupButton{text: text, value: value} = props) do
    Tag.content_tag(
      :div,
      Tag.content_tag(:button, text,
        type: :button,
        value: value,
        "phx-click": "set_species_category"
      ),
      class:
        props
        |> Map.from_struct()
        |> Enum.reduce(
          ["btn", "btn-xs"],
          &group_button_css/2
        )
    )
  end

  defp group_button_css({:selected?, false}, css), do: ["btn-outline" | css]

  defp group_button_css({:color, "" <> color}, css), do: ["btn-#{color}" | css]

  defp group_button_css({_prop, _val}, css), do: css
end
