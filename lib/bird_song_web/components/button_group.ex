defmodule BirdSongWeb.Components.GroupButton do
  use Phoenix.LiveComponent

  @enforce_keys [:text, :value, :phx_click, :phx_value]
  defstruct [:color, :phx_click, :phx_value, :text, :value, disabled?: false, selected?: false]

  @type t() :: %__MODULE__{
          color: String.t(),
          disabled?: boolean(),
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
        disabled={@button.disabled?}
        {[
          aria: [
            role: "checkbox",
            checked: @button.selected?,
            disabled: @button.disabled?
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
    |> Enum.reduce(["btn", "btn-xs"], &class(&1, button, &2))
  end

  defp class({:selected?, false}, %__MODULE__{}, css), do: ["btn-outline" | css]

  defp class({:color, "" <> color}, %__MODULE__{disabled?: false}, css),
    do: ["btn-#{color}" | css]

  defp class({:disabled?, true}, %__MODULE__{}, css), do: ["btn-disabled" | css]

  defp class({_prop, _val}, %__MODULE__{}, css), do: css
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
