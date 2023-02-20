defmodule BirdSongWeb.QuizLive do
  use Phoenix.LiveView
  use Phoenix.HTML

  alias Phoenix.LiveView.Socket
  alias Ecto.Changeset

  alias BirdSong.{
    Services,
    Services.Ebird,
    Quiz
  }

  # region is temporarily hard-coded; future version will take user input
  @region "US-NC-067"

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:text_input_class, @text_input_class)
     |> assign_new(:quiz, fn -> Quiz.changeset(%Quiz{region: @region}, %{}) end)
     |> assign_new(:tasks, fn -> %{} end)}
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center flex-col">
      <%= inner_content(assigns) %>
    </div>
    """
  end

  def inner_content(%{quiz: %Changeset{}} = assigns), do: new(assigns)
  def inner_content(%{quiz: %Quiz{}} = assigns), do: question(assigns)

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

      <div>
        <%= label q, :quiz_length, "Number of Questions" %>
        <%= text_input q, :quiz_length, class: @text_input_class %>
      </div>

      <%= submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
    """
  end

  def question(assigns) do
    ~H"""
    <%= page_title("What bird do you hear?") %>
    This is a new question
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
        Process.send(self(), {:fetch_birds_for_region, data}, [])

        {:noreply, assign(socket, :quiz, data)}

      %Changeset{} = changeset ->
        {:noreply, assign(socket, :quiz, changeset)}
    end
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{assigns: %{quiz: quiz}} = socket) do
    {:noreply, assign(socket, :quiz, Quiz.changeset(quiz, changes))}
  end

  ####################################
  ####################################
  ##  MESSAGE HANDLERS
  ##

  def handle_info(:get_recent_observations, socket) do
    task =
      Task.Supervisor.async_nolink(
        Services,
        Ebird,
        :get_recent_observations,
        [get_region(socket)]
      )

    {:noreply, remember_task(socket, task, :recent_observations)}
  end

  def handle_info({:fetch_birds_for_region, %Quiz{}}, socket) do
    {:noreply, socket}
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

    {:noreply,
     socket
     |> assign(:recent_observations, reduced)
     |> push_event(:recent_observations, %{data: reduced})}
  end

  defp handle_task_response({:ok, event_name}, socket, {:ok, response}) do
    {:noreply, push_event(socket, event_name, %{data: response})}
  end

  defp handle_task_response({:ok, event_name}, socket, {:error, error}) do
    {:noreply, push_event(socket, event_name, %{error: error})}
  end

  defp remember_task(%Socket{assigns: %{tasks: tasks}} = socket, %Task{ref: ref}, name) do
    assign(socket, :tasks, Map.put(tasks, ref, name))
  end

  defp forget_task(%Socket{assigns: %{tasks: tasks}} = socket, ref) when is_reference(ref) do
    {_, without} = Map.pop!(tasks, ref)
    assign(socket, :tasks, without)
  end

  defp get_region(%Socket{assigns: %{region: region}}), do: region

  defp reduce_recent_observations(%Ebird.Observation{} = obs, acc) do
    Map.update(acc, obs.species_code, [obs], &[obs | &1])
  end
end
