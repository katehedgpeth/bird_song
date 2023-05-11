defmodule BirdSongWeb.Components.Filters.BySpecies do
  use Phoenix.LiveComponent

  alias BirdSong.Bird

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton
  }

  @type bird_state() :: %{
          bird: Bird.t(),
          selected?: boolean()
        }

  def render(%{} = assigns) do
    ~H"""
    <div id={@id}>
      <h3>Limit to these birds (optional):</h3>

      <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-1">
        <%= for {category_name, birds} <- Enum.sort_by(@birds_by_category, &elem(&1, 0)) do %>
          <.species_group
            category_name={category_name}
            birds={birds}
          />
        <% end %>
      </div>
    </div>
    """
  end

  defp bird_filter_button(%{bird: %Bird{common_name: name}, selected?: selected?}, "" <> category) do
    %GroupButton{
      color: "primary",
      phx_click: "include?",
      phx_value: [bird: name, category: category],
      selected?: selected?,
      text: name,
      value: name
    }
  end

  defp bird_filter_buttons(%{birds: birds, category_name: category_name}) do
    assigns = %{
      birds: birds,
      category_name: category_name,
      buttons:
        birds
        |> Enum.map(&bird_filter_button(&1, category_name))
        |> Enum.sort_by(& &1.text, :desc)
    }

    ~H"""
    <div>
      <.live_component
        module={ButtonGroup}
        id={"bird-filters-" <> @category_name}
        buttons={@buttons}
      />
    </div>
    """
  end

  @spec bird_group_selection_state([bird_state()]) :: %{
          optional(true) => [bird_state()],
          optional(false) => [bird_state()]
        }
  defp bird_group_selection_state(birds) do
    Enum.group_by(birds, fn %{bird: %Bird{}, selected?: selected?} -> selected? end)
  end

  defp on_click_attrs_for_category(event, category) do
    [
      phx: [
        click: event,
        value: [category: category]
      ]
    ]
  end

  defp species_group(%{birds: _, category_name: _} = assigns) do
    ~H"""
    <div>
      <.species_filter_title birds={@birds} category_name={@category_name} />
      <.bird_filter_buttons birds={@birds} category_name={@category_name} />
    </div>
    """
  end

  defp species_filter_checkbox_attrs(%{true => _, false => _}), do: [indeterminate: true]
  defp species_filter_checkbox_attrs(%{true => _}), do: [checked: true]
  defp species_filter_checkbox_attrs(%{false => _}), do: []

  defp species_filter_checkbox(%{category_name: _name, birds: _birds} = assigns) do
    group_state = bird_group_selection_state(assigns[:birds])

    assigns =
      Map.merge(assigns, %{
        checkbox_attr: species_filter_checkbox_attrs(group_state),
        id: "species-filter-" <> assigns[:category_name],
        on_click: on_click_attrs_for_category("include?", assigns[:category_name]),
        text:
          case group_state do
            %{false => _} -> "Select all"
            %{} -> "Deselect all"
          end
      })

    ~H"""
    <div class="form-control">
      <label for={@id} class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          id={@id}
          class="checkbox checkbox-xs"
          {@checkbox_attr}
          {@on_click}
        />
        <span class="label-text">
          <%= @text %>
        </span>
      </label>
    </div>

    """
  end

  defp species_filter_title(%{birds: _, category_name: _} = assigns) do
    assigns =
      Map.put(
        assigns,
        :on_click,
        on_click_attrs_for_category("toggle_visibility", assigns[:category_name])
      )

    ~H"""
    <div>
      <div class="divider my-0.5"></div>
      <div class="flex justify-between">
        <%= @category_name %>
        <%= unless length(assigns[:birds]) === 1 do %>
          <.species_filter_checkbox birds={@birds} category_name={@category_name} />
        <% end %>
      </div>
    </div>
    """
  end
end
