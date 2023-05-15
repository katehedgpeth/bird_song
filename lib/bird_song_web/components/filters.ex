defmodule BirdSongWeb.Components.Filters do
  use Phoenix.LiveView

  alias BirdSong.Quiz

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.Visibility
  }

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  @type assigns() :: %{
          required(:services) => Services.t(),
          required(:region) => __MODULE__.Region.t(),
          optional(:by_species) => __MODULE__.BySpecies.t()
        }

  on_mount {BirdSong.PubSub, :subscribe}
  on_mount {QuizLive.Assign, :assign_services}

  @impl LiveView
  def mount(_params, _session, %Socket{} = socket) do
    {:ok, load_quiz_or_assign_defaults(socket)}
  end

  @impl LiveView
  def handle_event("region:" <> event, params, socket) do
    __MODULE__.Region.handle_event(event, params, socket)
  end

  def handle_event("include?", params, socket) do
    __MODULE__.BySpecies.handle_event("include?", params, socket)
  end

  def handle_event("start", %{}, socket) do
    BirdSong.PubSub.broadcast(socket, {:start, capture_state(socket)})
    {:noreply, socket}
  end

  def handle_event("toggle_visibility", %{"element" => element}, socket) do
    {:noreply, Visibility.toggle(socket, String.to_existing_atom(element))}
  end

  def handle_event("reset", _, socket) do
    {:noreply, assign_defaults(socket)}
  end

  @impl LiveView
  def handle_info(
        {:region_selected, %BirdSong.Region{} = region},
        %Socket{} = socket
      ) do
    {:noreply,
     socket.assigns
     |> __MODULE__.BySpecies.build_selected(%Quiz{region_code: region.code, birds: []})
     |> case do
       {:error, error} ->
         LiveView.put_flash(socket, :error, error)

       %{} = by_species ->
         LiveView.assign(socket, :by_species, by_species)
     end}
  end

  def handle_info(:change_region, socket) do
    {:noreply, assign_defaults(socket)}
  end

  # ---------- IGNORED MESSAGES ----------
  def handle_info({:start, _}, socket), do: ignore_message(socket)
  def handle_info({:quiz_created, _}, socket), do: ignore_message(socket)

  defp ignore_message(socket), do: {:noreply, socket}

  if Mix.env() === :test do
    @impl LiveView
    def handle_call(:socket, _, socket) do
      {:reply, socket, socket}
    end

    def handle_call(:assigns, _, socket) do
      {:reply, socket.assigns, socket}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp assign_defaults(%Socket{} = socket) do
    assign(socket, %{
      region: __MODULE__.Region.default_assigns(),
      by_species: nil,
      visibility: %Visibility{}
    })
  end

  defp capture_state(%Socket{} = socket) do
    [
      region_code: __MODULE__.Region.get_selected_code!(socket.assigns),
      birds: __MODULE__.BySpecies.get_selected_birds(socket.assigns)
    ]
  end

  defp load_quiz(%Socket{} = socket, %Quiz{} = quiz) do
    assigns = %{
      region: __MODULE__.Region.load_from_quiz(quiz),
      by_species: __MODULE__.BySpecies.build_selected(socket.assigns, quiz),
      visibility: %Visibility{}
    }

    case assigns do
      %{by_species: {:error, error_text}} ->
        socket
        |> LiveView.put_flash(:error, error_text)
        |> LiveView.assign(Map.drop(assigns, [:by_species]))

      %{by_species: %{}} ->
        LiveView.assign(socket, assigns)
    end
  end

  defp load_quiz_or_assign_defaults(%Socket{} = socket) do
    case Quiz.get_latest_by_session_id(socket.assigns[:session_id]) do
      %Quiz{} = quiz -> load_quiz(socket, quiz)
      nil -> assign_defaults(socket)
    end
  end

  #########################################################
  #########################################################
  ##
  ##  TEMPLATES
  ##
  #########################################################

  @doc """
  Used by other liveviews that want to include filters on their page
  """
  def render_filters(%{} = assigns) do
    assigns = %{
      socket: Map.fetch!(assigns, :socket),
      services:
        assigns
        |> Map.fetch!(:services)
        |> Map.fetch!(:ebird)
        |> Map.fetch!(:Regions)
        |> Map.fetch!(:parent)
        |> BirdSong.Services.Service.get_parent()
        |> Atom.to_string()
    }

    ~H"""
      <%=
        live_render @socket, __MODULE__,
          id: "filters",
          session: %{"services" => @services}
      %>
    """
  end

  @impl LiveView
  def render(%{} = assigns) do
    ~H"""
      <div class="gap-3">
        <.live_component module={__MODULE__.Region}  id={@region.id}, {Map.from_struct(@region)} />
        <.filters_after_region {assigns} />
      </div>
    """
  end

  defp filters_after_region(%{by_species: %{}} = assigns) do
    ~H"""
    <div>
      <div class="divider my-0.5"></div>
      <.live_component
        module={__MODULE__.BySpecies}
        id="filter-by-species"
        by_species={@by_species}
        visibility={@visibility}
      />
      <div class="divider my-0.5"></div>
      <div class="flex justify-around my-3">
        <button type="button" class="btn btn-outline btn-primary" phx-click="reset">
          Clear all filters
        </button>

        <button type="submit" class= "btn btn-primary" phx-click="start">
          Let's go!
        </button>
      </div>
    </div>
    """
  end

  defp filters_after_region(%{} = assigns) do
    ~H"""
    <span></span>
    """
  end
end
