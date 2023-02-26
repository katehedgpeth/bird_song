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

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:text_input_class, @text_input_class)
     |> reset_state()
     |> assign(:birds, %{})
     |> assign_new(:xeno_canto_cache, fn -> XenoCanto.Cache end)
     |> assign_new(:render_listeners, fn -> [] end)
     |> assign_new(:quiz, fn -> Quiz.changeset(%Quiz{region: @region}, %{}) end)
     |> assign_new(:tasks, fn -> %{} end)}
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
  def inner_content(%{current_bird: {%Bird{}, %Recording{}}} = assigns), do: question(assigns)

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
        %Socket{assigns: %{current_bird: {bird, %Recording{}}}} = socket
      ) do
    {:noreply, assign(socket, :current_bird, get_bird_and_recording(bird))}
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
     |> Map.keys()
     |> Enum.reduce(socket, &get_recording_for_bird(&2, &1))}
  end

  def handle_info({ref, response}, %Socket{} = socket) when is_reference(ref) do
    socket.assigns
    |> Map.fetch!(:tasks)
    |> Map.fetch(ref)
    |> handle_task_response(socket, response)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, socket) do
    {:noreply, forget_task(socket, ref)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid,
         {:timeout,
          {GenServer, :call, [XenoCanto.Cache, {:get_recording_from_api, bird_id}, _timeout]}}},
        socket
      ) do
    {:noreply,
     socket
     |> forget_task(ref)
     |> get_recording_for_bird(bird_id)}
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

  defp handle_task_response(:error, socket, _response) do
    # ignore messages from unknown tasks
    {:noreply, socket}
  end

  defp handle_task_response({:ok, :recent_observations}, socket, {:ok, recent_observations}) do
    reduced = Enum.reduce(recent_observations, %{}, &reduce_recent_observations/2)
    Process.send(self(), :get_recordings, [])

    {:noreply, assign(socket, :birds, reduced)}
  end

  defp handle_task_response(
         {:ok, {:recording, bird_id}},
         socket,
         {:ok, %Response{num_recordings: "0"}}
       ) do
    %Bird{common_name: common_name} = Map.fetch!(socket.assigns[:birds], bird_id)

    [
      "message=no_recordings",
      "bird_id=" <> bird_id,
      "common_name=" <> common_name
    ]
    |> Enum.join(" ")
    |> Logger.warn()

    {:noreply, remove_bird_with_no_recordings(socket, bird_id)}
  end

  defp handle_task_response({:ok, {:recording, bird_id}}, socket, {:ok, %Response{} = response}) do
    {:noreply,
     socket
     |> add_recordings_to_bird(bird_id, response)
     |> add_bird_to_quiz(bird_id)
     |> assign_next_bird()}
  end

  defp handle_task_response({:ok, name}, socket, response) do
    Logger.error(
      "error=unexpected_task_response name=#{inspect(name)} response=#{inspect(response)}"
    )

    {:noreply, socket}
  end

  defp remember_task(%Socket{assigns: %{tasks: tasks}} = socket, %Task{ref: ref}, name) do
    assign(socket, :tasks, Map.put(tasks, ref, name))
  end

  defp forget_task(%Socket{assigns: %{tasks: tasks}} = socket, ref) when is_reference(ref) do
    Logger.warn("api_calls_remaining=#{Kernel.map_size(tasks)}")
    {_, without} = Map.pop!(tasks, ref)
    assign(socket, :tasks, without)
  end

  defp get_region(%Socket{assigns: %{quiz: %Quiz{region: region}}}), do: region

  defp reset_state(%Socket{} = socket) do
    socket
    |> assign(:current_bird, nil)
    |> assign(:show_answer?, false)
    |> assign(:show_sono?, false)
  end

  defp reduce_recent_observations(%Ebird.Observation{} = obs, acc) do
    Map.update(
      acc,
      obs.sci_name,
      Bird.new(obs),
      &Bird.add_observation(&1, obs)
    )
  end

  defp get_recording_for_bird(%Socket{} = socket, bird_id) do
    remember_task(
      socket,
      Task.Supervisor.async_nolink(
        Services,
        XenoCanto,
        :get_recording,
        [bird_id, socket.assigns[:xeno_canto_cache]],
        timeout: @api_timeout
      ),
      {:recording, bird_id}
    )
  end

  defp add_recordings_to_bird(
         %Socket{assigns: %{birds: birds}} = socket,
         "" <> bird_id,
         %Response{} = response
       ) do
    assign(
      socket,
      :birds,
      Map.update!(
        birds,
        bird_id,
        &Bird.add_recordings(&1, response)
      )
    )
  end

  defp add_bird_to_quiz(%Socket{assigns: %{quiz: quiz}} = socket, bird_id) do
    assign(
      socket,
      :quiz,
      Quiz.add_bird(quiz, bird_id)
    )
  end

  defp assign_next_bird(
         %Socket{
           assigns: %{
             current_bird: nil,
             quiz: %Quiz{birds: [next | rest]} = quiz,
             birds: birds
           }
         } = socket
       ) do
    socket
    |> assign(:current_bird, get_next_bird_and_recording(birds, next))
    |> assign(:quiz, %{quiz | birds: rest})
  end

  defp assign_next_bird(%Socket{} = socket) do
    socket
  end

  defp remove_bird_with_no_recordings(socket, bird_id) do
    {_, birds} = Map.pop!(socket.assigns[:birds], bird_id)
    assign(socket, :birds, birds)
  end

  @spec get_next_bird_and_recording(%{required(String.t()) => Bird.t()}, String.t()) ::
          {Bird.t(), Recording.t()}
  defp get_next_bird_and_recording(%{} = birds, "" <> next_id) do
    birds
    |> Map.fetch!(next_id)
    |> get_bird_and_recording()
  end

  defp get_bird_and_recording(%Bird{recordings: recordings} = bird) do
    {bird, Enum.random(recordings)}
  end

  defp get_recording_source({%Bird{}, %Recording{file: file}}), do: file

  defp show_answer(%{
         show_answer?: true,
         current_bird: {%Bird{common_name: name}, %Recording{also: also}}
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

  defp show_answer(%{show_answer?: true, current_bird: {%Bird{common_name: name}, %Recording{}}}),
    do: content_tag(:div, name, class: "mx-auto text-center")

  defp show_answer(assigns),
    do: ~H"""
    <button phx-click="show_answer" class="btn btn-outline mx-auto block">Show Answer</button>
    """

  defp show_sono(%{
         show_sono?: true,
         current_bird: {%Bird{}, %Recording{sono: %{"large" => large_sono}}}
       }) do
    img_tag(large_sono)
  end

  defp show_sono(assigns) do
    ~H"""
    <button phx-click="show_sono" class="btn btn-outline">Show Sonogram</button>
    """
  end
end
