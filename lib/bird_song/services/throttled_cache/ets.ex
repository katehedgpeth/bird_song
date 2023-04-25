defmodule BirdSong.Services.ThrottledCache.ETS.ResponseError do
  defexception [:expected, :received]

  def message(%__MODULE__{expected: expected, received: %{__struct__: received}}) do
    do_message(expected, received, "module")
  end

  def message(%__MODULE__{expected: expected, received: received}) do
    do_message(expected, received, "format")
  end

  def do_message(expected, received, error_type) do
    """
    \n\n
    Services.ThrottledCache.ETS: Unexpected response #{error_type}

    expected -> #{inspect(expected)}
    received -> #{inspect(received)}

    """
  end
end

defmodule BirdSong.Services.ThrottledCache.ETS do
  require Logger
  use GenServer

  alias BirdSong.{
    Bird,
    Services.DataFile,
    Services.Service,
    Services.ThrottledCache
  }

  @type t() :: %__MODULE__{
          data_file_instance: pid(),
          ets_name: atom(),
          ets_table: :ets.table(),
          listeners: [pid()],
          service: Service.t(),
          tasks: %{reference() => Bird.t()}
        }

  @enforce_keys [:data_file_instance, :ets_name, :service]
  defstruct [
    :data_file_instance,
    :ets_name,
    :ets_opts,
    :ets_table,
    :service,
    listeners: [],
    tasks: %{}
  ]

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def clear_cache(pid) when is_pid(pid) do
    GenServer.cast(pid, :clear_cache)
  end

  def lookup(data, pid) do
    GenServer.call(pid, {:lookup, data})
  end

  def parse_from_disk(request, pid) when is_pid(pid) do
    GenServer.call(pid, {:parse_from_disk, request})
  end

  def read_from_disk(request, pid) when is_pid(pid) do
    GenServer.call(pid, {:read_from_disk, request})
  end

  @spec save_response({ThrottledCache.request_data(), response :: any()}, pid()) :: :ok
  def save_response({request_data, {:ok, response}}, pid) do
    GenServer.call(pid, {:save_response, request_data, response})
  end

  def save_response({_request_info, {:error, _error}}, _pid) do
    # don't save error responses
    {:error, :bad_response}
  end

  #########################################################
  #########################################################
  ##
  ##  TASK METHODS
  ##
  #########################################################

  def do_parse_from_disk(
        request,
        %__MODULE__{service: service} = state,
        # using parent instead of self() here to enable this to be called from a task
        parent
      )
      when is_pid(parent) do
    with {:ok, raw} <- do_read_from_disk(request, state) do
      parsed = Service.parse_response(service, Jason.decode!(raw), request)

      send(parent, {:save, {request, {:ok, parsed}}})

      {:ok, parsed}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def handle_call({:lookup, data}, _from, %__MODULE__{} = state) do
    {:reply, do_lookup(data, state), state}
  end

  def handle_call({:read_from_disk, bird}, _from, %__MODULE__{} = state) do
    {:reply, do_read_from_disk(bird, state), state}
  end

  def handle_call({:parse_from_disk, bird}, _from, %__MODULE__{} = state) do
    {:reply, do_parse_from_disk(bird, state, self()), state}
  end

  def handle_call({:save_response, request, response}, _from, %__MODULE__{} = state) do
    {:reply, do_save_response(request, response, state), state}
  end

  def handle_cast(:clear_cache, state) do
    {:noreply,
     state
     |> stop_table()
     |> start_table()}
  end

  def handle_info({:save, {request_data, {:ok, data}}}, %__MODULE__{} = state) do
    save_response_to_ets({request_data, {:ok, data}}, state)
    {:noreply, state}
  end

  def init(opts) do
    {:ok,
     opts
     |> __struct__()
     |> start_table()}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp do_lookup(data, %__MODULE__{} = state) do
    state
    |> Map.fetch!(:ets_table)
    |> :ets.lookup(ets_key(state, data))
    |> case do
      [{_, response}] -> {:ok, response}
      [] -> :not_found
    end
  end

  @spec do_save_response(
          any,
          %{__struct__: response_struct :: atom()},
          BirdSong.Services.ThrottledCache.ETS.t()
        ) :: :ok
  def do_save_response(
        request_data,
        response,
        %__MODULE__{} = state
      ) do
    :ok = verify_response_struct!(state, response)

    state.ets_table
    |> :ets.insert({ets_key(state, request_data), response})
    |> case do
      true ->
        Enum.each(state.listeners, &send(&1, {:response_saved_to_ets, request_data}))
    end
  end

  defp do_read_from_disk(request, %__MODULE__{
         data_file_instance: df_instance,
         service: service
       }) do
    DataFile.read(%DataFile.Data{request: request, service: service}, df_instance)
  end

  defp ets_key(%__MODULE__{service: %Service{module: module}}, request_data) do
    apply(module, :ets_key, [request_data])
  end

  defp save_response_to_ets(
         {request_data, {:ok, response}},
         %__MODULE__{} = state
       ) do
    :ok = verify_response_struct!(state, response)

    state
    |> Map.fetch!(:ets_table)
    |> :ets.insert({ets_key(state, request_data), response})
    |> case do
      true ->
        Enum.each(state.listeners, &send(&1, {:response_saved_to_ets, request_data}))
    end
  end

  defp start_table(%__MODULE__{} = state) do
    %{state | ets_table: :ets.new(state.ets_name, state.ets_opts)}
  end

  defp stop_table(%__MODULE__{ets_table: ets_table} = state) do
    :ets.delete(ets_table)
    %{state | ets_table: nil}
  end

  defp verify_response_struct!(%__MODULE__{service: %Service{} = service}, response) do
    expected = Service.response_module(service)

    case response do
      %{__struct__: ^expected} ->
        :ok

      {:ok, %{__struct__: ^expected}} ->
        :ok

      other ->
        raise __MODULE__.ResponseError.exception(expected: expected, received: other)
    end
  end
end
