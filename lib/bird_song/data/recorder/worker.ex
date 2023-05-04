defmodule BirdSong.Data.Recorder.Worker do
  alias BirdSong.{
    Bird,
    Data.Recorder,
    Services,
    Services.Flickr,
    Services.MacaulayLibrary,
    Services.Worker
  }

  @timeout :bird_song
           |> Application.compile_env(Recorder)
           |> Keyword.fetch!(:stream_timeout_ms)

  defstruct [
    :bird,
    :__from,
    :services,
    :images_response,
    :recordings_response,
    overwrite?: false,
    timeout: @timeout,
    __tasks: []
  ]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          services: Services.t(),
          images_response: Map.t(),
          recordings_response: Map.t(),
          timeout: integer(),
          __tasks: [{reference(), atom()}],
          __from: GenServer.from()
        }

  @spec fetch_data_for_bird(t()) ::
          Stream.t()
  def fetch_data_for_bird(%__MODULE__{} = state) do
    {:ok, server} = DynamicSupervisor.start_child(__MODULE__.GenServers, {__MODULE__, state})

    response = GenServer.call(server, :fetch_all_data, :infinity)

    :ok = DynamicSupervisor.terminate_child(__MODULE__.GenServers, server)
    response
  end

  def handle_call(
        :fetch_all_data,
        from,
        %__MODULE__{__from: nil} = state
      ) do
    {:noreply,
     [:images, :recordings]
     |> Enum.reduce(%{state | __from: from}, &maybe_start_task/2)
     |> maybe_reply()}
  end

  def maybe_start_task(key, %__MODULE__{overwrite?: true} = state) do
    start_task(key, state)
  end

  def maybe_start_task(key, %__MODULE__{bird: bird, overwrite?: false} = state) do
    key
    |> get_endpoint_for_task(state)
    |> Services.Worker.parse_from_disk(bird)
    |> case do
      :not_found ->
        start_task(key, state)

      {:ok, _} = response ->
        # overwrite? is false and a data file exists for this bird,
        # so do not call the service.
        Map.replace!(state, :"#{key}_response", response)
    end
  end

  def start_task(key, %__MODULE__{bird: bird, timeout: timeout, services: services} = state) do
    worker = Map.fetch!(services, key)
    %Services.Worker{module: module} = worker

    %Task{ref: task_ref} =
      Task.Supervisor.async_nolink(__MODULE__.Tasks, module, :get, [bird, worker],
        timeout: timeout
      )

    Map.update!(state, :__tasks, fn tasks -> [{task_ref, key} | tasks] end)
  end

  def handle_info({ref, {:ok, response}}, state) when is_reference(ref),
    do: handle_response({ref, {:ok, response}}, state)

  def handle_info({ref, {:error, error}}, state) when is_reference(ref),
    do: handle_response({ref, {:error, error}}, state)

  def handle_info({:DOWN, ref, :process, _pid, reason}, %__MODULE__{} = state) do
    {:noreply,
     state
     |> handle_downed_task(ref, reason)
     |> maybe_reply()}
  end

  defp get_endpoint_for_task(:images, %__MODULE__{
         services: %Services{images: %Flickr{PhotoSearch: %Worker{} = images}}
       }) do
    images
  end

  defp get_endpoint_for_task(:recordings, %__MODULE__{
         services: %Services{
           recordings: %MacaulayLibrary{Recordings: %Worker{} = recordings}
         }
       }) do
    recordings
  end

  defp handle_response({ref, response}, %__MODULE__{__tasks: tasks} = state) do
    {:noreply,
     Map.update!(
       state,
       tasks |> Enum.into(%{}) |> Map.fetch!(ref),
       &%{&1 | response: response}
     )}
  end

  @spec handle_downed_task(t(), reference(), atom()) :: t()
  defp handle_downed_task(%__MODULE__{__tasks: tasks} = state, ref, exit_reason) do
    tasks = Enum.into(tasks, %{})
    key = Map.fetch!(tasks, ref)
    tasks = tasks |> Map.delete(ref) |> Enum.into([])

    state
    |> Map.replace!(:__tasks, Enum.into(tasks, []))
    |> Map.update!(key, &%{&1 | exit_reason: exit_reason})
  end

  @spec maybe_reply(t()) :: t()
  defp maybe_reply(%__MODULE__{__tasks: []} = state) do
    # all tasks are finished, so we can reply and also terminate the server
    reply(state)
  end

  defp maybe_reply(%__MODULE__{} = state) do
    # at least one task has not finished yet,
    # so we are not ready to reply
    state
  end

  defp reply(state) do
    %__MODULE__{
      __from: from,
      bird: bird,
      images_response: images,
      recordings_response: recordings
    } = state

    GenServer.reply(from, %__MODULE__{
      bird: bird,
      images_response: images,
      recordings_response: recordings
    })

    state
  end
end
