defmodule BirdSongWeb.Components.Filters do
  use Phoenix.LiveView

  alias BirdSong.{
    Bird,
    Quiz,
    Services
  }

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.Visibility
  }

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  @type assigns() :: %{
          required(:by_family) => __MODULE__.ByFamily.t() | nil,
          required(:quiz_id) => integer() | nil,
          required(:region) => __MODULE__.Region.t(),
          required(:services) => Services.t(),
          required(:use_recent_observations?) => boolean(),
          required(:visibility) => Visibility.t()
        }

  @no_birds_error "
  There do not appear to be any known birds in that region.
  Please choose a different or broader region.
  "

  @no_observations_error "
  There are no recent observations in that region.
  "

  @not_available_error "
  We're sorry, but our service is not available at the moment. Please try again later.
  "

  on_mount(QuizLive.User)
  on_mount({BirdSong.PubSub, :subscribe})
  on_mount({QuizLive.Assign, :assign_services})

  def not_available_error(), do: @not_available_error

  @impl LiveView
  def mount(_params, _session, %Socket{} = socket) do
    {:ok, load_quiz_or_assign_defaults(socket)}
  end

  @impl LiveView
  def handle_event("region:" <> event, params, socket) do
    __MODULE__.Region.handle_event(event, params, socket)
  end

  def handle_event("include?", params, socket) do
    __MODULE__.ByFamily.handle_event("include?", params, socket)
  end

  def handle_event("start", %{}, socket) do
    BirdSong.PubSub.broadcast(socket, {:start, capture_state(socket)})
    {:noreply, socket}
  end

  def handle_event("use_recent_observations", %{}, socket) do
    {:noreply,
     socket
     |> LiveView.assign(
       :use_recent_observations?,
       not socket.assigns.use_recent_observations?
     )
     |> assign_region_birds(__MODULE__.ByFamily.get_selected_birds(socket.assigns.by_family))}
  end

  def handle_event("toggle_visibility", %{"element" => "families", "family" => family}, socket) do
    {:noreply, Visibility.toggle(socket, :families, family)}
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
        %Socket{assigns: %{region: %{selected: region}}} = socket
      ) do
    {:noreply, assign_region_birds(socket, [])}
  end

  def handle_info(:change_region, socket) do
    {:noreply, assign_defaults(socket)}
  end

  # ---------- IGNORED MESSAGES ----------
  def handle_info({:start, _}, socket), do: ignore_message(socket)

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
    assign(socket, get_default_assigns(socket.assigns.services))
  end

  @spec get_default_assigns(Services.t()) :: assigns()
  defp get_default_assigns(%Services{} = services) do
    %{
      by_family: nil,
      quiz_id: nil,
      region: __MODULE__.Region.default_assigns(),
      services: services,
      use_recent_observations?: true,
      visibility: %Visibility{}
    }
  end

  defp capture_state(%Socket{} = socket) do
    [
      region_code: __MODULE__.Region.get_selected_code!(socket.assigns),
      birds: get_selected_birds_for_quiz(socket),
      use_recent_observations?: socket.assigns.use_recent_observations?
    ]
  end

  defp error_text(:no_observations) do
    @no_observations_error
  end

  defp error_text(:no_codes_for_region) do
    @no_birds_error
  end

  defp error_text(%HTTPoison.Error{}) do
    @not_available_error
  end

  defp error_text({:bad_response, %HTTPoison.Response{}}) do
    @not_available_error
  end

  defp get_selected_birds_for_quiz(%Socket{} = socket) do
    case __MODULE__.ByFamily.get_selected_birds(socket.assigns.by_family) do
      [] -> __MODULE__.ByFamily.get_all_birds(socket.assigns.by_family)
      [_ | _] = selected -> selected
    end
  end

  defp load_quiz(%Socket{} = socket, %Quiz{use_recent_observations?: recent?} = quiz) do
    socket
    |> LiveView.assign(%{
      quiz_id: quiz.id,
      visibility: %Visibility{},
      region: __MODULE__.Region.load_from_quiz(quiz),
      use_recent_observations?: recent?,
      by_family: nil
    })
    |> assign_region_birds(quiz.birds)
  end

  defp load_quiz_or_assign_defaults(%Socket{} = socket) do
    socket.assigns.user.id
    |> Quiz.get_current_for_user!()
    |> case do
      nil -> assign_defaults(socket)
      %Quiz{} = quiz -> load_quiz(socket, quiz)
    end
  end

  defp assign_region_birds(%Socket{} = socket, selected_birds) do
    socket.assigns
    |> __MODULE__.Region.get_selected_code!()
    |> __MODULE__.RegionBirds.get_region_birds(socket.assigns)
    |> do_assign_region_birds(selected_birds, socket)
  end

  defp do_assign_region_birds({:error, error}, _, %Socket{} = socket) do
    LiveView.put_flash(socket, :error, error_text(error))
  end

  defp do_assign_region_birds([%{bird: %Bird{}} | _] = birds, selected_birds, %Socket{} = socket) do
    socket
    |> LiveView.assign(:by_family, __MODULE__.ByFamily.build_dict(birds, selected_birds))
    |> add_families_to_visibility()
  end

  defp add_families_to_visibility(%Socket{} = socket) do
    LiveView.assign(
      socket,
      :visibility,
      Visibility.add_families(socket.assigns.visibility, Map.keys(socket.assigns.by_family))
    )
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
      <div class="gap-3 w-full">
        <.live_component module={__MODULE__.Region}  id={@region.id}, {Map.from_struct(@region)} />
        <.filters_after_region {assigns} />
      </div>
    """
  end

  defp filters_after_region(%{by_family: %{}} = assigns) do
    ~H"""
    <div>
      <div class="divider my-0.5"></div>
      <.live_component
        module={__MODULE__.UseRecentObservations}
        id="use-recent-observations"
        checked={@use_recent_observations?}
      />

      <div class="divider my-0.5"></div>
      <.live_component
        module={__MODULE__.ByFamily}
        id="filter-by-family"
        by_family={@by_family}
        visibility={@visibility}
        use_recent_observations?={@use_recent_observations?}
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

  defp filters_after_region(%{region: %__MODULE__.Region{selected: %BirdSong.Region{}}} = assigns) do
    ~H"""
    <div class="flex flex-col items-center my-3">
      <progress class="progress progress-secondary w-3/4"></progress>
      <div>
        Fetching bird list for
        <%= @region.selected.short_name %>
        ...
      </div>
    </div>
    """
  end

  defp filters_after_region(%{region: %__MODULE__.Region{selected: :none}} = assigns) do
    ~H"""
    <div></div>
    """
  end
end
