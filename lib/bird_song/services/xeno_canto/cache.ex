defmodule BirdSong.Services.XenoCanto.Cache do
  use GenServer
  require Logger
  alias BirdSong.Services
  alias Services.{Helpers, XenoCanto, XenoCanto.Response}

  defstruct [:ets_table, throttled?: false, backlog: [], tasks: %{}]

  @table :xeno_canto

  @api_timeout :bird_song
               |> Application.compile_env!(:xeno_canto)
               |> Keyword.fetch!(:backlog_timeout_ms)

  def get(bird) do
    case get_from_cache(bird) do
      {:ok, recording} ->
        {:ok, recording}

      :not_found ->
        GenServer.call(__MODULE__, {:get_recording_from_api, bird}, @api_timeout)
    end
  end

  @spec get_from_cache(any) :: {:ok, Response.t()} | :not_found
  def get_from_cache(bird) do
    GenServer.call(__MODULE__, {:get_from_cache, bird})
  end

  def clear_cache() do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  def get_recording_from_api("" <> bird) do
    Logger.debug("message=sending_request service=xeno_canto bird=" <> bird)

    bird
    |> XenoCanto.url()
    |> HTTPoison.get()
    |> Helpers.parse_api_response()
    |> case do
      {:ok, raw} ->
        recording = Response.parse(raw)
        GenServer.cast(__MODULE__, {:save, {bird, recording}})
        {:ok, recording}

      error ->
        error
    end
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    {:ok, %__MODULE__{ets_table: start_table()}}
  end

  def handle_call(
        {:get_recording_from_api, bird},
        from,
        %__MODULE__{} = state
      ) do
    send(self(), :send_request)

    {:noreply,
     %{
       state
       | backlog:
           state
           |> Map.fetch!(:backlog)
           |> Enum.reverse([{from, bird}])
           |> Enum.reverse()
     }}
  end

  def handle_call({:get_from_cache, bird}, _from, %__MODULE__{} = state) do
    result =
      case :ets.lookup(state.ets_table, bird) do
        [{^bird, response}] -> {:ok, response}
        [] -> :not_found
      end

    {:reply, result, state}
  end

  def handle_cast({:save, {bird, recording}}, %__MODULE__{} = state) do
    :ets.insert(state.ets_table, {bird, recording})
    {:noreply, state}
  end

  def handle_cast(:clear_cache, %__MODULE__{} = state) do
    :ets.delete(state.ets_table)
    {:noreply, %{state | ets_table: start_table()}}
  end

  def handle_info(:send_request, %__MODULE__{backlog: []} = state) do
    # ignore message, because there are no requests to send
    {:noreply, state}
  end

  def handle_info(:send_request, %__MODULE__{throttled?: true} = state) do
    # do nothing, because requests are currently throttled.
    # :send_request will be called again when requests are unthrottled.
    {:noreply, state}
  end

  def handle_info(
        :send_request,
        %__MODULE__{
          throttled?: false,
          backlog: [{from, "" <> bird} | backlog]
        } = state
      ) do
    %Task{ref: ref} =
      Task.Supervisor.async_nolink(Services, __MODULE__, :get_recording_from_api, [bird])

    updated_state = %{
      state
      | throttled?: true,
        backlog: backlog,
        tasks: Map.put(state.tasks, ref, from)
    }

    {:noreply, updated_state}
  end

  def handle_info({ref, response}, %__MODULE__{} = state)
      when is_reference(ref) do
    from = Map.fetch!(state.tasks, ref)

    GenServer.reply(from, response)
    Process.send_after(self(), :unthrottle, Helpers.get_env(:xeno_canto, :throttle_ms))

    {:noreply, state}
  end

  def handle_info(:unthrottle, %__MODULE__{} = state) do
    send(self(), :send_request)
    {:noreply, %{state | throttled?: false}}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, %__MODULE__{} = state) do
    {_, tasks} = Map.pop!(state.tasks, ref)
    {:noreply, %{state | tasks: tasks}}
  end

  # used for saving data for tests
  def write_to_disk({:ok, response}, bird, true) do
    file_name =
      bird
      |> String.replace(" ", "_")
      |> Kernel.<>(".json")

    "test/mock_data/"
    |> Kernel.<>(file_name)
    |> Path.relative_to_cwd()
    |> File.write!(Jason.encode!(response))

    {:ok, response}
  end

  def write_to_disk(response, _, false), do: response

  defp start_table() do
    :ets.new(@table, [])
  end
end
