defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView
  use Phoenix.HTML

  alias Phoenix.LiveView.Socket
  alias Ecto.Changeset

  alias BirdSong.{
    Bird,
    Services,
    Services.Ebird,
    Services.XenoCanto,
    Quiz
  }

  alias XenoCanto.{Response, Recording}

  # region is temporarily hard-coded; future version will take user input
  @region "US-NC-067"

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  @api_timeout Application.compile_env(:bird_song, :throttled_backlog_timeout_ms)

  @type current_bird :: %{
          bird: Bird.t(),
          recording: Recording.t(),
          image: Photo.t()
        }

  defguard is_ets(maybe_ets) when is_reference(maybe_ets) or is_atom(maybe_ets)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:text_input_class, @text_input_class)
     |> reset_state()
     |> assign_new(:xeno_canto_cache, fn -> XenoCanto.Cache end)
     |> assign_new(:render_listeners, fn -> [] end)
     |> assign_new(:quiz, fn -> Quiz.changeset(%Quiz{region: @region}, %{}) end)
     |> assign_new(:tasks, fn -> :ets.new(__MODULE__.Tasks, []) end)
     |> assign_new(:birds, fn ->
       :ets.new(__MODULE__.Birds, [])
     end)
     |> update_bird_count()}
  end

  def render(assigns) do
    Enum.each(assigns[:render_listeners], &send(&1, assigns))

    ~H"""
    <div class="flex items-center flex-col">
      <%= inner_content(assigns) %>
    </div>
    """
  end

  def inner_content(%{quiz: %Changeset{}} = assigns), do: new(assigns)
  def inner_content(%{current_bird: nil} = assigns), do: loading(assigns)

  def inner_content(%{current_bird: %{bird: %Bird{}, recording: %Recording{}}} = assigns),
    do: question(assigns)

  def new(assigns) do
    ~H"""
    <%= page_title("How well do you know your bird songs?") %>
    <.form
      let={q}
      for={@quiz}
      id="settings"
      phx-change="validate"
      phx-submit="start"
      class="w-full md:w-1/2 flex flex-col space-y-4"
    >
      <div>
        <%=
          label q, :region, content_tag(:span, [
            "Region",
            content_tag(:span, " (can be city, state, or country)", class: "italic")
          ])
        %>
        <%= text_input q, :region, disabled: true, class: @text_input_class %>
      </div>

      <%= submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
    """
  end

  def question(assigns) do
    ~H"""
    <%= page_title("What bird do you hear?") %>
    <div class="flex gap-10 flex-col">
      <%= content_tag :audio, [], autoplay: true, src: get_recording_source(@current_bird) %>
      <div class="flex justify-center gap-5">
        <button phx-click="change_recording" class="btn btn-outline">Hear a different recording of this bird</button>
        <button phx-click="next" class="btn btn-secondary">Skip to next bird</button>
      </div>
      <div class="bg-slate-100 p-10 w-full">
        <%= show_answer(assigns) %>
      </div>
      <%= show_sono(assigns) %>
    </div>
    """
  end

  def loading(assigns) do
    ~H"""
    <h2>Loading...</h2>
    """
  end

  defp page_title("" <> title) do
    content_tag(:h1, title, class: "mb-4")
  end

  ####################################
  ####################################
  ##  EVENT HANDLERS
  ##

  def handle_event("start", %{"quiz" => changes}, %Socket{assigns: %{quiz: quiz}} = socket) do
    case Quiz.changeset(quiz, changes) do
      %Changeset{errors: [], data: data} ->
        Process.send(self(), :get_recent_observations, [])
        {:noreply, assign(socket, :quiz, data)}

      %Changeset{} = changeset ->
        {:noreply, assign(socket, :quiz, changeset)}
    end
  end

  def handle_event("start", %{}, %Socket{} = socket) do
    Process.send(self(), :get_recent_observations, [])
    {:noreply, assign(socket, :quiz, %Quiz{region: @region})}
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{assigns: %{quiz: quiz}} = socket) do
    {:noreply, assign(socket, :quiz, Quiz.changeset(quiz, changes))}
  end

  def handle_event("validate", %{}, %Socket{} = socket) do
    {:noreply, socket}
  end

  def handle_event("next", _, %Socket{} = socket) do
    {:noreply,
     socket
     |> reset_state()
     |> assign_next_bird()}
  end

  def handle_event(
        "change_recording",
        _,
        %Socket{assigns: %{current_bird: current_bird, xeno_canto_cache: xc_cache}} = socket
      ) do
    {:noreply, assign(socket, :current_bird, update_current_recording(current_bird, xc_cache))}
  end

  def handle_event("show_answer", _, %Socket{} = socket) do
    {:noreply, assign(socket, :show_answer?, true)}
  end

  def handle_event("show_sono", _, %Socket{} = socket) do
    {:noreply, assign(socket, :show_sono?, true)}
  end

  ####################################
  ####################################
  ##  MESSAGE HANDLERS
  ##

  def handle_info(:get_recent_observations, socket) do
    task =
      Task.Supervisor.async(
        Services,
        Ebird,
        :get_recent_observations,
        [get_region(socket)]
      )

    {:noreply, remember_task(socket, task, :recent_observations)}
  end

  def handle_info(
        :get_recordings,
        %Socket{assigns: %{birds: birds}} = socket
      ) do
    {:noreply,
     birds
     |> :ets.tab2list()
     |> Enum.map(&elem(&1, 1))
     |> Enum.reduce(socket, &get_recordings_for_bird(&2, &1))}
  end

  def handle_info({ref, response}, %Socket{} = socket) when is_reference(ref) do
    socket
    |> lookup_task(ref)
    |> handle_task_response(socket, response)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, socket) do
    {:noreply, forget_task(socket, ref)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid,
         {:timeout, {GenServer, :call, [XenoCanto.Cache, {:get_from_api, bird}, _timeout]}}},
        socket
      ) do
    {:noreply,
     socket
     |> forget_task(ref)
     |> get_recordings_for_bird(bird)}
  end

  def handle_info({:register_render_listener, pid}, socket) do
    {:noreply,
     assign(
       socket,
       :render_listeners,
       [pid | socket.assigns[:render_listeners]]
     )}
  end

  def handle_info({:xeno_canto_cache_pid, cache}, socket) do
    {:noreply, assign(socket, :xeno_canto_cache, cache)}
  end

  #

  ####################################
  ####################################
  ##  PRIVATE METHODS
  ##

  defp handle_task_response({:not_found, ref}, socket, _response) when is_reference(ref) do
    # ignore messages from unknown tasks
    {:noreply, socket}
  end

  defp handle_task_response({:ok, :recent_observations}, socket, {:ok, recent_observations}) do
    Enum.each(recent_observations, &save_observation(&1, socket.assigns[:birds]))
    Process.send(self(), :get_recordings, [])

    {:noreply, update_bird_count(socket)}
  end

  defp handle_task_response(
         {:ok, {:recording, "" <> sci_name}},
         socket,
         {:ok, %Response{num_recordings: "0"}}
       ) do
    {:ok, %Bird{sci_name: sci_name, common_name: common_name}} = lookup_bird(socket, sci_name)

    [
      "message=no_recordings",
      "bird_id=" <> sci_name,
      "common_name=" <> common_name
    ]
    |> Enum.join(" ")
    |> Logger.warn()

    {:noreply, remove_bird_with_no_recordings(socket, sci_name)}
  end

  defp handle_task_response(
         {:ok, {:recording, %Bird{} = bird}},
         socket,
         {:ok, %Response{}}
       ) do
    {:noreply,
     socket
     |> add_bird_to_quiz(bird)
     |> assign_next_bird()}
  end

  defp handle_task_response({:ok, name}, socket, response) do
    Logger.error(
      "error=unexpected_task_response name=#{inspect(name)} response=#{inspect(response)}"
    )

    {:noreply, socket}
  end

  defp remember_task(%Socket{assigns: %{tasks: tasks}} = socket, %Task{ref: ref}, name) do
    true = :ets.insert(tasks, {ref, name})
    socket
  end

  defp forget_task(%Socket{assigns: %{tasks: tasks}} = socket, ref) when is_reference(ref) do
    Logger.warn("api_calls_remaining=#{tasks |> :ets.tab2list() |> length()}")
    :ets.delete(tasks, ref)
    socket
  end

  defp get_region(%Socket{assigns: %{quiz: %Quiz{region: region}}}), do: region

  defp reset_state(%Socket{} = socket) do
    socket
    |> assign(:current_bird, nil)
    |> assign(:show_answer?, false)
    |> assign(:show_sono?, false)
    |> assign(:show_image?, false)
  end

  @spec save_observation(Ebird.Observation.t(), :ets.table()) :: :ok
  defp save_observation(%Ebird.Observation{sci_name: sci_name} = obs, birds_ets)
       when is_ets(birds_ets) do
    case lookup_bird(birds_ets, sci_name) do
      {:ok, %Bird{} = bird} ->
        update_bird(birds_ets, Bird.add_observation(bird, obs))

      :not_found ->
        true = :ets.insert(birds_ets, {sci_name, Bird.new(obs)})
        :ok
    end
  end

  @spec get_recordings_for_bird(Socket.t(), Bird.t()) :: Socket.t()
  defp get_recordings_for_bird(%Socket{} = socket, %Bird{} = bird) do
    remember_task(
      socket,
      Task.Supervisor.async_nolink(
        Services,
        XenoCanto,
        :get_recordings,
        [bird, socket.assigns[:xeno_canto_cache]],
        timeout: @api_timeout
      ),
      {:recording, bird}
    )
  end

  # @spec add_recordings_to_bird(Socket.t(), Bird.t(), Response.t()) :: Socket.t()
  # defp add_recordings_to_bird(
  #        %Socket{} = socket,
  #        %Bird{} = bird,
  #        %Response{} = response
  #      ) do
  #   update_bird(socket, Bird.add_recordings(bird, response))
  #   socket
  # end

  def lookup_task(%Socket{assigns: %{tasks: tasks_ets}}, ref) when is_reference(ref) do
    case :ets.lookup(tasks_ets, ref) do
      [{^ref, task}] -> {:ok, task}
      [] -> {:not_found, ref}
    end
  end

  @spec lookup_bird(:ets.table() | Socket.t(), String.t()) :: {:ok, Bird.t()} | :not_found
  defp lookup_bird(%Socket{assigns: %{birds: birds_ets}}, "" <> sci_name) do
    lookup_bird(birds_ets, sci_name)
  end

  defp lookup_bird(birds_ets, "" <> sci_name) when is_ets(birds_ets) do
    case :ets.lookup(birds_ets, sci_name) do
      [{^sci_name, %Bird{} = bird}] -> {:ok, bird}
      [] -> :not_found
    end
  end

  @spec update_bird(:ets.table(), Bird.t()) :: Socket.t() | :ok
  defp update_bird(birds_ets, %Bird{sci_name: sci_name} = bird) when is_ets(birds_ets) do
    true = :ets.insert(birds_ets, {sci_name, bird})
    :ok
  end

  defp add_bird_to_quiz(%Socket{assigns: %{quiz: quiz}} = socket, %Bird{sci_name: sci_name}) do
    assign(
      socket,
      :quiz,
      Quiz.add_bird(quiz, sci_name)
    )
  end

  defp assign_next_bird(
         %Socket{
           assigns: %{
             current_bird: nil,
             quiz: %Quiz{birds: [next | rest]} = quiz
           }
         } = socket
       ) do
    socket
    |> get_current_bird(next)
    |> assign(:quiz, %{quiz | birds: rest})
  end

  defp assign_next_bird(%Socket{} = socket) do
    socket
  end

  @spec remove_bird_with_no_recordings(Socket.t(), String.t()) :: Socket.t()
  defp remove_bird_with_no_recordings(%{assigns: %{birds: birds}} = socket, bird_id) do
    :ets.delete(birds, bird_id)
    update_bird_count(socket)
  end

  @spec get_current_bird(Socket.t(), String.t()) :: current_bird()
  defp get_current_bird(%Socket{assigns: %{birds: birds}} = socket, "" <> next_id)
       when is_ets(birds) do
    birds
    |> lookup_bird(next_id)
    |> do_get_current_bird(socket)
  end

  @spec do_get_current_bird({:ok, Bird.t()} | :error, Socket.t()) :: %{
          bird: Bird.t(),
          recording: Recording.t(),
          image: Photo.t()
        }
  defp do_get_current_bird(
         {:ok, %Bird{} = bird},
         %Socket{assigns: %{xeno_canto_cache: xc_cache}} = socket
       ) do
    assign(
      socket,
      :current_bird,
      %{
        bird: bird,
        recording: nil,
        image: nil
      }
      |> update_current_recording(xc_cache)
      |> update_current_image()
    )
  end

  @spec update_current_recording(current_bird(), pid()) :: current_bird()
  defp update_current_recording(%{bird: %Bird{} = bird} = current_bird, cache) do
    {:ok, %Response{recordings: recordings}} = XenoCanto.get_recordings(bird, cache)

    Map.replace!(current_bird, :recording, Enum.random(recordings))
  end

  defp update_current_image(%{bird: %Bird{}} = current_bird) do
    current_bird
  end

  defp update_bird_count(%Socket{assigns: %{birds: birds_ets}} = socket) do
    assign(
      socket,
      :bird_count,
      birds_ets
      |> :ets.tab2list()
      |> Kernel.length()
    )
  end

  defp get_recording_source(%{recording: %Recording{file: file}}), do: file

  defp show_answer(%{
         show_answer?: true,
         current_bird: %{
           bird: %Bird{common_name: name},
           recording: %Recording{also: also},
           image: _
         }
       })
       when length(also) > 0,
       do:
         content_tag(
           :div,
           [
             name,
             content_tag(:div, ["Also audible: ", Enum.map(also, &content_tag(:div, [&1]))],
               class: "text-black/40 italic"
             )
           ],
           class: "text-center"
         )

  defp show_answer(%{
         show_answer?: true,
         current_bird: %{bird: %Bird{common_name: name}}
       }),
       do: content_tag(:div, name, class: "mx-auto text-center")

  defp show_answer(assigns),
    do: ~H"""
    <button phx-click="show_answer" class="btn btn-outline mx-auto block">Show Answer</button>
    """

  defp show_sono(%{
         show_sono?: true,
         current_bird: %{recording: %Recording{sono: %{"large" => large_sono}}}
       }) do
    img_tag(large_sono)
  end

  defp show_sono(assigns) do
    ~H"""
    <button phx-click="show_sono" class="btn btn-outline">Show Sonogram</button>
    """
  end
end
