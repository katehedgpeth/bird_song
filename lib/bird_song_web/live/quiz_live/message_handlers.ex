defmodule BirdSongWeb.QuizLive.MessageHandlers do
  require Logger
  use BirdSongWeb.QuizLive.Assign

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.XenoCanto,
    Services.Ebird,
    Services.Flickr
  }

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.EtsTables
  }

  def handle_info(:get_region_species_codes, socket) do
    {:noreply, QuizLive.Services.get_region_species_codes(socket)}
  end

  def handle_info(
        {:get_recent_observations, tries: tries},
        %Socket{assigns: %{max_api_tries: max}} = socket
      )
      when tries >= max do
    {:noreply,
     socket
     |> Phoenix.LiveView.clear_flash()
     |> Phoenix.LiveView.put_flash(
       :error,
       "eBird is not responding to our requests at the moment. Please try again later."
     )}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, socket) do
    {:noreply, EtsTables.Tasks.forget_task(socket, ref)}
  end

  def handle_info({ref, response}, %Socket{} = socket)
      when is_reference(ref) do
    socket
    |> EtsTables.Tasks.lookup_task(ref)
    |> handle_task_response(socket, response)
  end

  ####################################
  ####################################
  ##  USED IN TESTS
  ##

  def handle_info({:register_render_listener, pid}, socket) do
    {:noreply,
     assign(
       socket,
       :render_listeners,
       [pid | socket.assigns[:render_listeners]]
     )}
  end

  def handle_info({:services, %Services{} = services}, socket) do
    {:noreply, assign(socket, :services, services)}
  end

  def handle_call(:socket, _from, %Socket{} = socket) do
    {:reply, socket, socket}
  end

  def handle_call(:kill_all_tasks, _from, socket) do
    {:reply, EtsTables.Tasks.kill_all_tasks(socket), socket}
  end

  ####################################
  ####################################
  ##  PRIVATE METHODS
  ##

  @spec handle_task_response(
          {:ok, any()} | {:not_found, reference()},
          Socket.t(),
          Helpers.api_response()
        ) :: {:noreply, Socket.t()}
  defp handle_task_response({:not_found, ref}, socket, _response)
       when is_reference(ref) do
    # ignore messages from unknown tasks
    Logger.warn("received message from unknown task")
    {:noreply, socket}
  end

  defp handle_task_response(
         {:ok, :recent_observations},
         socket,
         {:ok, %Ebird.Observations.Response{observations: observations}}
       ) do
    observations
    |> Enum.map(& &1.sci_name)
    |> Bird.get_many_by_sci_name()
    |> case do
      [%Bird{} | _] = birds ->
        {:noreply,
         socket
         |> assign(:birds, Enum.shuffle(birds))
         |> QuizLive.assign_next_bird()}
    end
  end

  defp handle_task_response(
         {:ok, {:recording, "" <> sci_name}},
         socket,
         {:ok, %XenoCanto.Response{num_recordings: "0"}}
       ) do
    {:ok,
     %Bird{
       common_name: common_name
     }} = Bird.get_by_sci_name(sci_name)

    [
      "message=no_recordings",
      "bird_id=" <> sci_name,
      "common_name=" <> common_name
    ]
    |> Enum.join(" ")
    |> Logger.warn()

    {:noreply, socket}
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

  defp handle_task_response(
         {:ok, {:images, %Bird{}}},
         socket,
         {:ok, %Flickr.Response{}}
       ) do
    {:noreply, QuizLive.assign_next_bird(socket)}
  end

  defp handle_task_response({:ok, name}, socket, {:error, error}) do
    {:noreply,
     Phoenix.LiveView.put_flash(
       socket,
       :error,
       "#{inspect(name)} task returned an error: \n\n #{inspect(error)}"
     )}
  end

  defp handle_task_response({:ok, name}, socket, response) do
    Logger.error(
      "error=unexpected_task_response name=#{inspect(name)} response=#{inspect(response)}"
    )

    {:noreply, socket}
  end

  defp add_bird_to_quiz(%Socket{assigns: %{quiz: quiz}} = socket, %Bird{sci_name: sci_name}) do
    assign(
      socket,
      :quiz,
      Quiz.add_bird(quiz, sci_name)
    )
  end
end
