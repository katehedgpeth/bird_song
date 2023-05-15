defmodule BirdSongWeb.Components.Filters.Region do
  use Phoenix.LiveComponent

  alias BirdSong.Quiz
  alias Phoenix.LiveView.Socket
  alias Phoenix.HTML

  @id "filter-region"

  defstruct id: @id,
            options: [],
            regions: [],
            selected: :none,
            typed: :none

  @type t() :: %__MODULE__{
          regions: [BirdSong.Region.t()],
          typed: String.t() | :none,
          selected: BirdSong.Region.t() | :none
        }

  def default_assigns() do
    struct!(__MODULE__, regions: BirdSong.Region.all())
  end

  def get_selected_code!(%{region: %{}} = assigns) do
    assigns.region.selected.code
  end

  @spec load_from_quiz(Quiz.t()) :: t()
  def load_from_quiz(%Quiz{region_code: "" <> region_code}) do
    %__MODULE__{
      selected: BirdSong.Region.from_code!(region_code)
    }
  end

  def handle_event(
        "type",
        # typed value is 3 or more letters
        %{"region" => <<_::binary-size(3), _::binary>> = region},
        %Socket{} = socket
      ) do
    {:noreply,
     socket.assigns[:region]
     |> Map.put(:typed, region)
     |> get_suggestions()
     |> update_assigned(socket)}
  end

  def handle_event(
        "type",
        # typed value is only 1 or 2 letters
        %{"region" => "" <> _},
        %Socket{assigns: %{region: %__MODULE__{}}} = socket
      ) do
    {:noreply, socket}
  end

  def handle_event("select", %{"region" => code}, socket) do
    {:noreply,
     socket.assigns[:region]
     |> set_selected(code, socket)
     |> update_assigned(socket)}
  end

  def handle_event("change", %{}, socket) do
    BirdSong.PubSub.broadcast(socket, :change_region)

    {:noreply, socket}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp event_name("" <> name), do: "region:" <> name

  defp get_suggestions(%__MODULE__{typed: "" <> _} = state) do
    downcased = String.downcase(state.typed)

    %{
      state
      | options:
          Enum.filter(
            state.regions,
            &(String.downcase(&1.short_name) =~ downcased)
          )
    }
  end

  defp set_selected(%__MODULE__{} = state, "" <> region_code, %Socket{} = socket) do
    region = BirdSong.Region.from_code!(region_code)

    BirdSong.PubSub.broadcast(socket, {:region_selected, region})

    %{state | selected: region}
  end

  defp update_assigned(%__MODULE__{} = state, %Socket{} = socket) do
    assign(socket, :region, state)
  end

  #########################################################
  #########################################################
  ##
  ##  TEMPLATES
  ##
  #########################################################

  def render(%__MODULE__{} = assigns) do
    ~H"""
    <div id={@id}>
      <%= do_render(assigns) %>
    </div>
    """
  end

  def render(%{} = assigns) do
    assigns
    |> Map.take(Map.keys(%__MODULE__{regions: []}))
    |> Keyword.new()
    |> __struct__()
    |> render()
  end

  defp do_render(%__MODULE__{selected: %BirdSong.Region{} = region}) do
    selected_region_with_change_button(region)
  end

  defp do_render(%__MODULE__{} = assigns) do
    region_form(assigns)
  end

  defp selected_region_with_change_button(%BirdSong.Region{} = assigns) do
    ~H"""
    <h3>Region:</h3>
    <div class="flex justify-between gap-3">
      <span class="text-xl font-bold"> <%= @full_name %> </span>
      <button
        type="button"
        phx-click={event_name("change")}
        class="btn btn-secondary btn-xs"
      >
        Change
      </button>
    </div>
    """
  end

  defp region_form(%__MODULE__{} = assigns) do
    assigns = %{
      id: assigns.id <> "-form",
      options: assigns.options,
      form:
        assigns
        |> Map.take([:region])
        |> Phoenix.HTML.FormData.to_form([])
    }

    ~H"""
      <form id={@id} >
        <div>
          <.region_label field={@form[:region]} />
          <.input_with_dropdown field={@form[:region]} options={@options} />
        </div>
      </form>
    """
  end

  defp region_label(%{field: %HTML.FormField{}} = assigns) do
    ~H"""
      <label for={@field.id} class="block">
        <span>
          Region
          <span class="italic">
            (can be city, state, or country)
          </span>
        </span>
      </label>
    """
  end

  defp input_with_dropdown(%{field: _, options: _} = assigns) do
    ~H"""
      <div class="dropdown dropdown-open block">
        <.region_input field={@field} />
        <%= if length(@options) > 0 do %>
          <.suggestions options={@options} />
        <% end %>
      </div>
    """
  end

  defp suggestions(%{options: _} = assigns) do
    assigns =
      Map.put(assigns, :class, [
        "dropdown-content",
        "menu",
        "p-2",
        "shadow",
        "bg-base-100",
        "rounded-box",
        "w-52"
      ])

    ~H"""
      <ul
        class={@class}
        tabindex="0"
        style="position:static;"
        aria-role="listbox"
      >
        <%= for region <- @options do %>
          <li
            phx-click={event_name("select")}
            phx-value-region={region.code}
            tabindex="0"
            aria-role="option"
          >
            <%= region.full_name %>
          </li>
        <% end %>
      </ul>

    """
  end

  defp region_input(%{field: %HTML.FormField{}} = assigns) do
    ~H"""
      <input
        type="text"
        id={@field.id}
        name={@field.name}
        value={@field.value}
        phx-change={event_name("type")}
        phx-debounce="3"
        class={~w(
          input
          input-bordered
          block
          w-full
          disabled:text-black/40
          disabled:italic
        )}
      />
    """
  end
end
