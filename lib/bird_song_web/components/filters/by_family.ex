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
            body:
              assigns
              |> Map.take([:by_family, :visibility])
              |> family_groups()
          )
        }
      />
    </div>
    """
  end

  defp by_family_title(%{} = assigns) do
    ~H"""
      <h3>Select specific birds or families (optional)</h3>
    """
  end

  defp bird_filter_button(%{bird: %Bird{common_name: name}, selected?: selected?}, "" <> family) do
    %GroupButton{
      color: "primary",
      phx_click: "include?",
      phx_value: [bird: name, family: family],
      selected?: selected?,
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
      <div class="border-b-1 border-b-black-200 last:border-b-0">
        <.live_component
          module={Collapse}
          id={"family-group-" <> @family_name}
          assigns={struct(Collapse, [
            state: @visibility.families[@family_name],
            element: "families",
            icon_type: :caret,
            phx_value: [ family: @family_name ],
            title:
              assigns
              |> Map.take([:birds, :family_name])
              |> family_filter_title(),
            body: assigns
            |> Map.take([:birds, :family_name])
            |> bird_filter_buttons()
          ])}
      />
      </div>
    """
  end

  defp family_groups(%{} = assigns) do
    ~H"""
      <div class="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-4 gap-3">
        <%= for {family_name, birds} <- Enum.sort_by(@by_family, &elem(&1, 0)) do %>
          <.family_group
            family_name={family_name}
            birds={birds}
            visibility={@visibility}
          />
        <% end %>
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
end
