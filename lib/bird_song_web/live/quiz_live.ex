defmodule BirdSongWeb.QuizLive do
  use Phoenix.LiveView
  alias Phoenix.LiveView.Socket
  alias BirdSong.Services
  alias BirdSong.Services.Ebird

  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send(self(), :get_bird_list, [])

    {:ok, assign_new(socket, :tasks, fn -> %{} end)}
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

  def handle_info(:get_bird_list, socket) do
    task =
      Task.Supervisor.async_nolink(
        Services,
        Ebird,
        :get_region_list,
        ["US-NC-067"]
      )

    {:noreply, remember_task(socket, task, :bird_list)}
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
end
