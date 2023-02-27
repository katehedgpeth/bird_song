defmodule BirdSongWeb.QuizLive.MessageHandlers do
  require Logger
  alias Phoenix.{LiveView, LiveView.Socket}

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.XenoCanto,
    Services.Ebird
  }

  alias BirdSongWeb.{QuizLive, QuizLive.Caches, QuizLive.EtsTables}

  def handle_info(:get_recent_observations, socket) do
    task =
      Task.Supervisor.async(
        Services,
        Ebird,
        :get_recent_observations,
        [get_region(socket)]
      )

    {:noreply, EtsTables.Tasks.remember_task(socket, task, :recent_observations)}
  end

  def handle_info(
        :start_throttled_data_collection,
        %Socket{} = socket
      ) do
    {:noreply, EtsTables.Tasks.start_tasks_for_all_birds(socket)}
  end

  def handle_info({ref, response}, %Socket{} = socket) when is_reference(ref) do
    socket
    |> EtsTables.Tasks.lookup_task(ref)
    |> handle_task_response(socket, response)
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, socket) do
    {:noreply, EtsTables.Tasks.forget_task(socket, ref)}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid,
         {:timeout, {GenServer, :call, [XenoCanto.Cache, {:get_from_api, bird}, _timeout]}}},
        socket
      ) do
    {:noreply,
     socket
     |> EtsTables.Tasks.forget_task(ref)
     |> EtsTables.Tasks.start_task(bird, :recordings)}
  end

  def handle_info({:register_render_listener, pid}, socket) do
    {:noreply,
     LiveView.assign(
       socket,
       :render_listeners,
       [pid | socket.assigns[:render_listeners]]
     )}
  end

  def handle_info({:caches, %Caches{} = caches}, socket) do
    {:noreply, LiveView.assign(socket, :caches, caches)}
  end

  ####################################
  ####################################
  ##  PRIVATE METHODS
  ##

  defp handle_task_response({:not_found, ref}, socket, _response) when is_reference(ref) do
    # ignore messages from unknown tasks
    {:noreply, socket}
  end

  defp handle_task_response({:ok, :recent_observations}, socket, {:ok, recent_observations}) do
    Enum.each(
      recent_observations,
      &EtsTables.Birds.save_observation(socket, &1)
    )

    Process.send(self(), :start_throttled_data_collection, [])

    {:noreply, EtsTables.Birds.update_bird_count(socket)}
  end

  defp handle_task_response(
         {:ok, {:recording, "" <> sci_name}},
         socket,
         {:ok, %XenoCanto.Response{num_recordings: "0"}}
       ) do
    {:ok, %Bird{sci_name: sci_name, common_name: common_name}} =
      EtsTables.Birds.lookup_bird(socket, sci_name)

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
         {:ok, {:recordings, %Bird{} = bird}},
         socket,
         {:ok, %XenoCanto.Response{}}
       ) do
    {:noreply,
     socket
     |> add_bird_to_quiz(bird)
     |> QuizLive.assign_next_bird()}
  end

  defp handle_task_response({:ok, name}, socket, response) do
    Logger.error(
      "error=unexpected_task_response name=#{inspect(name)} response=#{inspect(response)}"
    )

    {:noreply, socket}
  end

  @spec remove_bird_with_no_recordings(Socket.t(), String.t()) :: Socket.t()
  defp remove_bird_with_no_recordings(%{assigns: %{birds: birds}} = socket, bird_id) do
    :ets.delete(birds, bird_id)
    EtsTables.Birds.update_bird_count(socket)
  end

  defp add_bird_to_quiz(%Socket{assigns: %{quiz: quiz}} = socket, %Bird{sci_name: sci_name}) do
    LiveView.assign(
      socket,
      :quiz,
      Quiz.add_bird(quiz, sci_name)
    )
  end

  defp get_region(%Socket{assigns: %{quiz: %Quiz{region: region}}}), do: region
end
