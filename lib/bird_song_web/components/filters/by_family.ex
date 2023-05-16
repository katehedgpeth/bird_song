defmodule BirdSongWeb.Components.Filters.ByFamily do
  use Phoenix.LiveComponent

  alias BirdSong.{
    Bird
  }

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.Collapse,
    Components.GroupButton,
    QuizLive.Visibility
  }

  @type bird_state() :: Assigns.bird_state()

  @type family_name() :: String.t()

  @type t() :: %{family_name() => [bird_state()]}

  @impl Phoenix.LiveComponent
  defdelegate handle_event(name, params, socket), to: __MODULE__.Assigns

  @spec build_dict([bird_state()], [Bird.t()]) :: t() | {:error, String.t()}
  defdelegate build_dict(all, selected), to: __MODULE__.Assigns
  defdelegate get_selected_birds(family_dict), to: __MODULE__.Assigns
  defdelegate get_all_birds(family_dict), to: __MODULE__.Assigns

  @impl Phoenix.LiveComponent
  def render(%{} = assigns) do
    ~H"""
    <div>
      <.live_component
        module={Collapse}
        id={@id <> "-collapse"}
        assigns={
          struct(Collapse,
            state: @visibility.by_family,
            element: "by_family",
            icon_type: :caret,
            title: by_family_title(%{}),
            body: family_groups(%{
              by_family: @by_family,
              visibility: @visibility,
              use_recent_observations?: @use_recent_observations?
            })
          )
        }
      />
    </div>
    """
  end

  defp by_family_title(%{} = assigns) do
    ~H"""
      <h3 class="py-2">Select specific birds or families (optional)</h3>
    """
  end

  defp bird_filter_button(
         %{bird: %Bird{common_name: name}, disabled?: disabled?, selected?: selected?},
         "" <> family
       ) do
    %GroupButton{
      color: "primary",
      phx_click: "include?",
      phx_value: [bird: name, family: family],
      selected?: selected?,
      disabled?: disabled?,
      text: name,
      value: name
    }
  end

  defp bird_filter_buttons(%{birds: birds, family_name: family_name}) do
    live_component(%{
      module: ButtonGroup,
      id: "bird-filters-" <> family_name,
      buttons:
        birds
        |> Enum.map(&bird_filter_button(&1, family_name))
        |> Enum.sort_by(& &1.text, :desc)
    })
  end

  @spec bird_group_selection_state([bird_state()]) :: %{
          optional(true) => [bird_state()],
          optional(false) => [bird_state()]
        }
  defp bird_group_selection_state(birds) do
    Enum.group_by(birds, fn %{bird: %Bird{}, selected?: selected?} -> selected? end)
  end

  defp family_group(%{birds: _, family_name: _, visibility: %Visibility{}} = assigns) do
    ~H"""
      <div class={
        [
          "border-b-1",
          "border-b-black-200",
          "last:border-b-0"
          | disabled_group_classes(@birds)
        ]
      }>
        <.live_component
          module={Collapse}
          id={"family-group-" <> @family_name}
          assigns={struct(Collapse, [
            state: Map.fetch!(@visibility.families, @family_name),
            element: "families",
            icon_type: :caret,
            phx_value: [ family: @family_name ],
            title: family_filter_title(%{
                birds: @birds,
                family_name: @family_name
              }),
            body: bird_filter_buttons(%{
              birds: @birds,
              family_name: @family_name,
            })
          ])}
      />
      </div>
    """
  end

  defp family_groups(%{} = assigns) do
    ~H"""
      <div>
        <.filtered_species_note use_recent_observations?={@use_recent_observations?} />
        <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-3">
          <%= for {family_name, birds} <- Enum.sort_by(@by_family, &elem(&1, 0)) do %>
            <.family_group
              family_name={family_name}
              birds={birds}
              visibility={@visibility}
            />
          <% end %>
        </div>
      </div>
    """
  end

  defp family_filter_checkbox_attrs(%{true => _, false => _}), do: [indeterminate: true]
  defp family_filter_checkbox_attrs(%{true => _}), do: [checked: true]
  defp family_filter_checkbox_attrs(%{false => _}), do: []

  defp family_filter_checkbox(%{family_name: _name, birds: _birds} = assigns) do
    group_state = bird_group_selection_state(assigns[:birds])

    assigns =
      Map.merge(assigns, %{
        checkbox_attr: family_filter_checkbox_attrs(group_state),
        id: "family-filter-" <> assigns.family_name
      })

    ~H"""
    <div class="form-control">
      <label for={@id} class="label cursor-pointer justify-start gap-3">
        <input
          type="checkbox"
          id={@id}
          class="checkbox checkbox-xs"
          {[
            phx: [
              click: "include?",
              value: [ family: @family_name ]
            ]
          ]}
          {@checkbox_attr}
        />
      </label>
    </div>

    """
  end

  defp family_filter_title(%{birds: _, family_name: _} = assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-center">
        <%= @family_name %>
        <.family_filter_checkbox birds={@birds} family_name={@family_name} />
      </div>
    </div>
    """
  end

  defp filtered_species_note(%{} = assigns) do
    ~H"""
      <%= if @use_recent_observations? === true do %>
        <p class="text-xs text-gray-600 italic">
          * Families and species that have not been observed in the last 30 days are grayed out.
        </p>
      <% end %>
    """
  end

  defp disabled_group_classes([%{bird: _} | _] = birds) do
    case Enum.all?(birds, & &1.disabled?) do
      true -> ["text-gray-300"]
      false -> []
    end
  end
end
