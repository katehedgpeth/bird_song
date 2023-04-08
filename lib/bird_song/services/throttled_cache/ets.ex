defmodule BirdSong.Services.ThrottledCache.ETS do
  require Logger
  use GenServer

  alias BirdSong.{
    Bird,
    Services.DataFile,
    Services.Helpers,
    Services.Service
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
    response_module =
      service
      |> Service.module()
      |> Module.concat(:Response)

    case do_read_from_disk(request, state) do
      {:ok, str} ->
        data =
          str
          |> Jason.decode!()
          |> response_module.parse(request)

        send(parent, {:save, {request, {:ok, data}}})

        {:ok, data}

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

  def handle_info({:DOWN, ref, :process, _pid, :normal}, %__MODULE__{} = state) do
    state =
      Map.update!(state, :tasks, fn tasks ->
        {tasks, _} = Map.pop(tasks, ref)
        tasks
      end)

    if Kernel.map_size(state.tasks) === 0 do
      Helpers.log(
        [message: "seeding_finished", time: DateTime.now!("Etc/UTC")],
        __MODULE__,
        :warning
      )
    end

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

  def do_save_response(
        request_data,
        response,
        %__MODULE__{
          ets_table: ets_table,
          listeners: listeners,
          service: service
        } = state
      ) do
    # require the response to be structured correctly
    response_module = Service.response_module(service)
    %{__struct__: ^response_module} = response

    ets_table
    |> :ets.insert({ets_key(state, request_data), response})
    |> case do
      true ->
        Enum.each(listeners, &send(&1, {:response_saved_to_ets, request_data}))
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

  defp response_module(%__MODULE__{service: %Service{module: module}}) do
    Module.concat(module, :Response)
  end

  defp save_response_to_ets(
         {request_data, {:ok, response}},
         %__MODULE__{} = state
       ) do
    response_module = response_module(state)
    %{__struct__: ^response_module} = response

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
end
