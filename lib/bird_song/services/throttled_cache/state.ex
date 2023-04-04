defmodule BirdSong.Services.ThrottledCache.State do
  require Logger

  alias BirdSong.{
    Bird,
    Services,
    Services.ThrottledCache,
    Services.DataFile,
    Services.XenoCanto,
    Services.Flickr,
    Services.Helpers,
    Services.Ebird,
    Services.Service
  }

  @type request_data() :: {GenServer.from(), any()}

  @type t() :: %__MODULE__{
          base_url: String.t(),
          backlog: [request_data],
          data_file_instance: GenServer.server() | nil,
          data_folder_path: String.t(),
          ets_table: :ets.table(),
          ets_name: atom(),
          ets_opts: [:ets.table_type()],
          request_listeners: [pid()],
          scraper: atom() | {atom(), pid()},
          service: Service.t(),
          tasks: %{reference() => request_data()},
          throttled?: boolean(),
          throttle_ms: integer(),
          write_responses_to_disk?: boolean()
        }

  @enforce_keys [:data_folder_path, :base_url]
  defstruct [
    :base_url,
    :data_folder_path,
    :ets_table,
    :ets_name,
    :scraper,
    :service,
    ets_opts: [],
    backlog: [],
    data_file_instance: DataFile,
    request_listeners: [],
    tasks: %{},
    throttled?: false,
    throttle_ms:
      :bird_song
      |> Application.compile_env(ThrottledCache)
      |> Keyword.fetch!(:throttle_ms),
    write_responses_to_disk?: false
  ]

  defguard is_known_service(service)
           when service in [
                  XenoCanto,
                  Flickr,
                  ThrottledCacheUnderTest,
                  Ebird.Observations,
                  Ebird.Recordings,
                  Ebird.RegionCodes
                ]

  def new(opts) do
    __MODULE__
    |> struct(opts)
    |> verify_state()
    |> start_table()
  end

  def start_table({:ok, %__MODULE__{} = state}), do: start_table(state)

  def start_table(%__MODULE__{ets_name: ets_name, ets_opts: ets_opts} = state) do
    Map.replace!(state, :ets_table, :ets.new(ets_name, ets_opts))
  end

  def clear_cache(%__MODULE__{} = state) do
    state
    |> Map.fetch!(:ets_table)
    |> :ets.delete()

    start_table(state)
  end

  def lookup(%__MODULE__{} = state, data) do
    state
    |> ets_table()
    |> :ets.lookup(ets_key(state, data))
    |> case do
      [{_, response}] -> {:ok, response}
      [] -> :not_found
    end
  end

  @spec should_send_request?(t()) :: boolean
  def should_send_request?(%__MODULE__{backlog: []}) do
    # no, because there are no requests to send
    false
  end

  def should_send_request?(%__MODULE__{throttled?: true}) do
    # no, because requests are currently throttled.
    # :send_request will be called again when requests are unthrottled.
    false
  end

  def should_send_request?(%__MODULE__{throttled?: false}) do
    # requests are not throttled and the backlog is not empty,
    # so we can send the next request.
    true
  end

  @spec send_request(t()) :: t()
  def send_request(%__MODULE__{throttled?: false} = state) do
    case get_next_request_from_backlog(state) do
      {:ok, {{from, data}, state}} ->
        side_effects(state, {:request, data})
        start_get_from_api_task(state, from, data)

      {:error, :backlog_empty} ->
        state
    end
  end

  def side_effects(%__MODULE__{} = state, {:request, data}) do
    log_request(state, data, :start)
    notify_listeners(state, data, :start)
  end

  defp start_get_from_api_task(%__MODULE__{} = state, from, request_data) do
    %Service{module: module} = Map.fetch!(state, :service)

    %Task{ref: ref} =
      Task.Supervisor.async(
        Services.Tasks,
        module,
        :get_from_api,
        [request_data, state],
        timeout: :infinity
      )

    state
    |> Map.replace!(:throttled?, true)
    |> Map.update!(:tasks, &Map.put(&1, ref, {from, request_data}))
  end

  defp get_next_request_from_backlog(%__MODULE__{backlog: [{from, data} | backlog]} = state) do
    {:ok, {{from, data}, Map.replace!(state, :backlog, backlog)}}
  end

  defp get_next_request_from_backlog(%__MODULE__{backlog: []}) do
    {:error, :backlog_empty}
  end

  def save_response(
        %__MODULE__{service: %Service{module: module}} = state,
        {request_data, {:ok, response}}
      ) do
    response_module = Module.concat(module, :Response)
    %{__struct__: ^response_module} = response

    state
    |> Map.fetch!(:ets_table)
    |> :ets.insert({ets_key(state, request_data), response})
    |> case do
      true -> :ok
    end
  end

  def save_response(%__MODULE__{}, {_request_info, {:error, _error}}) do
    # don't save error responses
    {:error, :bad_response}
  end

  def add_request_to_backlog(%__MODULE__{} = state, from, request_data) do
    Map.update!(
      state,
      :backlog,
      &(&1 |> Enum.reverse([{from, request_data}]) |> Enum.reverse())
    )
  end

  def forget_task(%__MODULE__{} = state, ref) do
    Map.update!(
      state,
      :tasks,
      &(&1
        |> Map.pop!(ref)
        |> elem(1))
    )
  end

  def unthrottle(%__MODULE__{} = state) do
    Map.replace!(state, :throttled?, false)
  end

  def register_request_listener(%__MODULE__{} = state, pid) do
    Map.update!(state, :request_listeners, &[pid | &1])
  end

  def notify_listeners(
        %__MODULE__{request_listeners: listeners, service: service},
        request,
        start_or_end
      ) do
    Enum.each(
      listeners,
      &send(
        &1,
        build_request_message(start_or_end, request, service)
      )
    )
  end

  def update_write_config(%__MODULE__{} = state, write_to_disk?) do
    case write_to_disk? do
      true ->
        ensure_data_file_started(state)

      false ->
        state
    end
    |> Map.replace!(:write_responses_to_disk?, write_to_disk?)
  end

  def write_to_disk?(%__MODULE__{write_responses_to_disk?: write_to_disk?}), do: write_to_disk?

  def data_folder_path(%__MODULE__{data_folder_path: "" <> data_folder_path}) do
    data_folder_path
  end

  def seed_ets_table(%__MODULE__{} = state) do
    Bird
    |> BirdSong.Repo.all()
    |> List.first()
    |> List.wrap()
    |> Enum.reduce(state, &start_ets_seed_task/2)
  end

  def start_ets_seed_task(%Bird{} = bird, %__MODULE__{} = state) do
    %Task{ref: ref} =
      Task.Supervisor.async(Services.Tasks, __MODULE__, :add_data_file_to_ets, [bird, state])

    Map.update!(state, :tasks, &Map.put(&1, ref, {:seed_data_task, bird.common_name}))
  end

  def add_data_file_to_ets(
        %Bird{} = bird,
        %__MODULE__{} = state
      ) do
    service_module =
      state
      |> service()
      |> Service.module()

    response_module = Module.concat(service_module, :Response)

    case DataFile.read(%DataFile.Data{request: bird, service: service(state)}) do
      {:ok, str} ->
        data =
          str
          |> Jason.decode!()
          |> response_module.parse()

        state
        |> service()
        |> Map.fetch!(:whereis)
        |> send({:save, {bird, {:ok, data}}})

      {:error, {error, path}} ->
        Helpers.log(
          [
            error: "data_file_read_error",
            reason: error,
            bird: bird.common_name,
            path: path
          ],
          service_module,
          :error
        )
    end
  end

  defp ensure_data_file_started(%__MODULE__{} = state) do
    pid =
      case GenServer.start(state.data_file_instance, []) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Map.replace!(state, :data_file_instance, pid)
  end

  defp ets_table(%__MODULE__{ets_table: ets_table}), do: ets_table

  defp ets_key(%__MODULE__{service: %Service{module: module}}, request_data),
    do: apply(module, :ets_key, [request_data])

  @spec service(t()) :: Service.t()
  def service(%__MODULE__{service: %Service{} = service}), do: service

  @spec build_request_message(:start | {:end, any()}, {GenServer.from(), any()}, Service.t()) ::
          {:start_request | :end_request,
           %{
             optional(:bird) => Bird.t(),
             optional(:response) => any(),
             optional(:region) => String.t(),
             module: atom(),
             time: DateTime.t()
           }}
  defp build_request_message(start_or_end, request, %Service{} = service) do
    details =
      service
      |> Service.module()
      |> apply(:message_details, [request])

    {
      message_name(start_or_end),
      service
      |> default_message()
      |> Map.merge(details)
      |> maybe_add_response_to_message(start_or_end)
    }
  end

  defp maybe_add_response_to_message(message, :start) do
    message
  end

  defp maybe_add_response_to_message(message, {:end, response}) do
    Map.put(message, :response, response)
  end

  @spec default_message(Service.t()) :: %{module: atom(), time: DateTime.t()}
  defp default_message(%Service{module: module}) do
    %{
      module: module,
      time: DateTime.now!("Etc/UTC")
    }
  end

  defp message_name(:start), do: :start_request
  defp message_name({:end, _response}), do: :end_request

  defp log_request(%__MODULE__{service: %Service{module: module}}, request, start_or_end)
       when start_or_end in [:start, :end] do
    [message: "#{start_or_end}_request"]
    |> log_request_details(request)
    |> Helpers.log(module, :debug)
  end

  defp log_request_details(log, {:recent_observations, region}) do
    [{:region, region} | log]
  end

  defp log_request_details(log, %Bird{common_name: common_name}) do
    [{:bird, common_name} | log]
  end

  defp log_request_details(log, _) do
    log
  end

  defp verify_state(
         %__MODULE__{
           base_url: "" <> _,
           service: %Service{module: service_module, whereis: service_pid},
           ets_name: ets_name
         } = state
       )
       when is_known_service(service_module) and is_pid(service_pid) and ets_name !== nil,
       do: {:ok, state}
end
