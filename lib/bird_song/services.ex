defmodule BirdSong.Services do
  use GenServer
  alias BirdSong.Services.DataFile
  alias BirdSong.Bird
  alias __MODULE__.Service
  @env Application.compile_env(:bird_song, BirdSong.Services)
  @images Keyword.fetch!(@env, :images)
  @recordings Keyword.fetch!(@env, :recordings)
  @observations Keyword.fetch!(@env, :observations)
  @timeout Keyword.fetch!(@env, :stream_timeout_ms)

  defstruct [
    :bird,
    :__from,
    images: %Service{
      module: @images
    },
    recordings: %Service{
      module: @recordings
    },
    observations: %Service{
      module: @observations
    },
    overwrite?: false,
    timeout: @timeout,
    __tasks: []
  ]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          images: Service.t(),
          recordings: Service.t(),
          timeout: integer(),
          __tasks: [{reference(), atom()}],
          __from: GenServer.from()
        }

  @spec fetch_data_for_bird(t()) ::
          Stream.t()
  def fetch_data_for_bird(
        %__MODULE__{
          bird: %Bird{},
          images: %Service{},
          recordings: %Service{}
        } = state
      ) do
    {:ok, server} = DynamicSupervisor.start_child(__MODULE__.GenServers, {__MODULE__, state})

    response = GenServer.call(server, :fetch_all_data, :infinity)

    :ok = DynamicSupervisor.terminate_child(__MODULE__.GenServers, server)
    response
  end

  def ensure_started() do
    Enum.reduce(
      [:images, :recordings, :observations],
      %__MODULE__{},
      fn key, state -> Map.update!(state, key, &Service.ensure_started/1) end
    )
  end

  def start_link(%__MODULE__{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  @spec init(BirdSong.Services.t()) :: {:ok, BirdSong.Services.t()}
  def init(%__MODULE__{} = state) do
    {:ok, state}
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
    service = Map.fetch!(state, key)

    case DataFile.read(%DataFile.Data{
           service: service,
           request: bird
         }) do
      {:ok, saved_response} ->
        # overwrite? is false and a data file exists for this bird,
        # so do not call the service.
        Map.update!(
          state,
          key,
          &Map.replace!(
            &1,
            :response,
            # at this point in development, we do not need to preserve response headers;
            # this may change in the future.
            apply(service.module, :parse_response, [
              {:ok, %HTTPoison.Response{status_code: 200, body: saved_response}},
              bird
            ])
          )
        )

      {:error, {:enoent, _path}} ->
        start_task(key, state)
    end
  end

  def start_task(key, %__MODULE__{bird: bird, timeout: timeout} = state) do
    service = Map.fetch!(state, key)
    %Service{module: module} = service

    %Task{ref: task_ref} =
      Task.Supervisor.async_nolink(__MODULE__.Tasks, module, :get, [bird, service],
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

  def terminate(reason, _state) do
    IO.inspect(reason, label: "terminated")
    :ok
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
      images: images,
      recordings: recordings
    } = state

    GenServer.reply(from, %__MODULE__{
      bird: bird,
      images: images,
      recordings: recordings
    })

    state
  end
end
