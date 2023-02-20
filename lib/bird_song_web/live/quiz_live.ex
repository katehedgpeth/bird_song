defmodule BirdSongWeb.QuizLive do
  use Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias BirdSong.Services
  alias BirdSong.Services.Ebird

  # region is temporarily hard-coded; future version will take user input
  @region "US-NC-067"

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send(self(), :get_recent_observations, [])

    {:ok,
     socket
     |> assign(:region, @region)
     |> assign_new(:tasks, fn -> %{} end)}
  end

  def render(assigns) do
    ~H"""
    Hello world!
    """
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

  def handle_info({ref, response}, %Socket{} = socket) when is_reference(ref) do
    socket.assigns
    |> Map.fetch!(:tasks)
    |> Map.fetch(ref)
    |> handle_task_response(socket, response)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, socket) do
    {:noreply, forget_task(socket, ref)}
  end

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
