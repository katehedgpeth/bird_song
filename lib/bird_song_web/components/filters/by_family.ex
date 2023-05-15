defmodule BirdSongWeb.Components.Filters.ByFamily do
  use Phoenix.LiveComponent

  alias BirdSong.{
    Bird
  }

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton,
    QuizLive.Visibility
  }

  @type bird_state() :: %{
          bird: Bird.t(),
          selected?: boolean()
        }

  @type family_name() :: String.t()

  @type t() :: %{family_name() => [bird_state()]}

  @impl Phoenix.LiveComponent
  defdelegate handle_event(name, params, socket), to: __MODULE__.Assigns

  @spec build_selected(Map.t(), Quiz.t()) :: t() | {:error, String.t()}
  defdelegate build_selected(assigns, quiz), to: __MODULE__.Assigns
  defdelegate get_selected_birds(socket), to: __MODULE__.Assigns

  defp collapse_state(%Visibility{by_family: :hidden}), do: "collapse-close"
  defp collapse_state(%Visibility{by_family: :shown}), do: "collapse-open"

  @impl Phoenix.LiveComponent
  def render(%{} = assigns) do
    ~H"""
    <div
      id={@id}
      class={["collapse", "collapse-plus", collapse_state(@visibility)]}
    >
      <input type="checkbox" />
      <div
        class="collapse-title"
        {[
          phx: [
            click: "toggle_visibility",
            value: [element: "by_family"]
          ]
        ]}
      >
        <h3>Select specific birds or families (optional):</h3>
      </div>

      <%= if @visibility.by_family === :shown do %>
        <.family_groups by_family={@by_family} />
      <% end %>
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

  defp family_group(%{birds: _, category_name: _} = assigns) do
    ~H"""
    <div>
      <.family_filter_title birds={@birds} category_name={@category_name} />
      <.bird_filter_buttons birds={@birds} category_name={@category_name} />
    </div>
    """
  end

  defp family_groups(%{} = assigns) do
    ~H"""
      <div class="collapse-content">
        <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-3">
          <%= for {category_name, birds} <- Enum.sort_by(@by_family, &elem(&1, 0)) do %>
            <.family_group
              category_name={category_name}
              birds={birds}
            />
          <% end %>
        </div>
      </div>
    """
  end

  defp family_filter_checkbox_attrs(%{true => _, false => _}), do: [indeterminate: true]
  defp family_filter_checkbox_attrs(%{true => _}), do: [checked: true]
  defp family_filter_checkbox_attrs(%{false => _}), do: []

  defp family_filter_checkbox(%{category_name: _name, birds: _birds} = assigns) do
    group_state = bird_group_selection_state(assigns[:birds])

    assigns =
      Map.merge(assigns, %{
        checkbox_attr: family_filter_checkbox_attrs(group_state),
        id: "family-filter-" <> assigns[:category_name],
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

  defp family_filter_title(%{birds: _, category_name: _} = assigns) do
    ~H"""
    <div>
      <div class="divider my-0.5"></div>
      <div class="flex justify-between">
        <%= @category_name %>
        <%= unless length(assigns[:birds]) === 1 do %>
          <.family_filter_checkbox birds={@birds} category_name={@category_name} />
        <% end %>
      </div>
    </div>
    """
  end
end
