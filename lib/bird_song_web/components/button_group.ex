defmodule BirdSongWeb.Components.GroupButton do
  use Phoenix.LiveComponent

  @enforce_keys [:text, :value, :phx_click, :phx_value]
  defstruct [:color, :phx_click, :phx_value, :text, :value, selected?: false]

  @type t() :: %__MODULE__{
          color: String.t(),
          phx_click: String.t(),
          phx_value: keyword(String.t()),
          selected?: boolean(),
          text: String.t(),
          value: String.t()
        }

  def render(%{button: %__MODULE__{}} = assigns) do
    ~H"""
    <div id={@id} class={class(@button)}>
      <button
        type="button"
        {[
          aria: [
            role: "checkbox",
            checked: @button.selected?
          ],
          phx: [
            click: @button.phx_click,
            value: @button.phx_value,
          ]
        ]}
      >
        <%= @button.text %>
      </button>
    </div>
    """
  end

  defp class(%__MODULE__{} = button) do
    button
    |> Map.from_struct()
    |> Enum.reduce(["btn", "btn-xs"], &class/2)
  end

  defp class({:selected?, false}, css), do: ["btn-outline" | css]

  defp class({:color, "" <> color}, css), do: ["btn-#{color}" | css]

  defp class({_prop, _val}, css), do: css
end

defmodule BirdSongWeb.Components.ButtonGroup do
  use Phoenix.LiveComponent
  alias BirdSongWeb.Components.GroupButton

  def render(%{buttons: [%GroupButton{} | _]} = assigns) do
    assigns =
      case assigns do
        %{alphabetize?: true} -> Map.update!(assigns, :buttons, &alphabetize_buttons/1)
        _ -> assigns
      end

    ~H"""
    <div class="flex flex-wrap gap-2" id={@id}>
      <%= for button <- @buttons do %>
        <.live_component module={GroupButton} id={button.value} button={button} />
      <% end %>
    </div>
    """
  end

  defp alphabetize_buttons([%GroupButton{} | _] = buttons) do
    Enum.sort_by(buttons, & &1.text)
  end
end
