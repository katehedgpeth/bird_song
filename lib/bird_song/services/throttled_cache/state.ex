defmodule BirdSong.Services.ThrottledCache.State.Supervisors do
  defstruct [:ets]

  @type t() :: %__MODULE__{
          ets: GenServer.server()
        }
end

defmodule BirdSong.Services.ThrottledCache.State do
  require Logger

  alias BirdSong.Services.RequestThrottler

  alias BirdSong.{
    Bird,
    Services.ThrottledCache,
    Services.ThrottledCache.State.Supervisors,
    Services.ThrottledCache.ETS,
    Services.DataFile,
    Services.XenoCanto,
    Services.Flickr,
    Services.Helpers,
    Services.Ebird,
    Services.Service
  }

  @type request_ets_item() :: %{
          from: GenServer.from(),
          request_data: ThrottledCache.request_data()
        }

  @type t() :: %__MODULE__{
          base_url: String.t(),
          data_file_instance: GenServer.server() | nil,
          data_folder_path: String.t(),
          ets_table: :ets.table(),
          ets_name: atom(),
          ets_opts: [:ets.table_type()],
          listeners: [pid()],
          requests: :ets.table(),
          scraper: atom() | {atom(), pid()},
          service: Service.t(),
          supervisors: Supervisors.t(),
          throttled?: boolean(),
          throttler: GenServer.server(),
          throttle_ms: integer(),
          write_responses_to_disk?: boolean()
        }

  @enforce_keys [:data_folder_path, :base_url]
  defstruct [
    :base_url,
    :data_folder_path,
    :ets_table,
    :ets_name,
    :requests,
    :scraper,
    :service,
    :throttler,
    ets_opts: [],
    backlog: [],
    data_file_instance: DataFile,
    listeners: [],
    supervisors: %__MODULE__.Supervisors{},
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
                  Ebird.Regions,
                  Ebird.RegionSpeciesCodes
                ]

  def new(opts) do
    opts
    |> Keyword.update!(:throttler, &ensure_throttler_started/1)
    |> __struct__()
    |> ensure_data_file_started()
    |> verify_state()
    |> start_ets()
  end

  @spec clear_cache(t()) :: t()
  def clear_cache(%__MODULE__{supervisors: %Supervisors{ets: ets}} = state) do
    ETS.clear_cache(ets)

    state
  end

  @spec handle_response(t(), RequestThrottler.Response.t()) :: t()
  def handle_response(%__MODULE__{} = state, %RequestThrottler.Response{} = response) do
    %{request_data: request_data, from: from} = get_request_from_ets(state, response)

    notify_listeners(state, request_data, {:end, response})

    maybe_write_to_disk(state, response, request_data)

    :ok = send_response(state, response, {request_data, from})

    state
  end

  def lookup(%__MODULE__{supervisors: %Supervisors{ets: pid}}, data) do
    ETS.lookup(data, pid)
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

  def side_effects(%__MODULE__{} = state, {:request, data}) do
    log_request(state, data, :start)
    notify_listeners(state, data, :start)
  end

  @spec save_response(t(), {ThrottledCache.request_data(), response :: any()}) :: :ok
  def save_response(%__MODULE__{supervisors: %Supervisors{ets: pid}}, {request_data, response}) do
    ETS.save_response({request_data, response}, pid)
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
    Map.update!(state, :listeners, &[pid | &1])
  end

  def notify_listeners(
        %__MODULE__{listeners: listeners, service: service},
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

  def read_from_disk(%__MODULE__{supervisors: %Supervisors{ets: ets}}, request) do
    ETS.read_from_disk(request, ets)
  end

  def parse_from_disk(%__MODULE__{supervisors: %Supervisors{ets: ets}}, request) do
    case ETS.parse_from_disk(request, ets) do
      {:error, {:enoent, _}} -> :not_found
      result -> result
    end
  end

  @spec save_request_to_ets(
          HTTPoison.Request.t(),
          GenServer.from(),
          ThrottledCache.request_data(),
          BirdSong.Services.ThrottledCache.State.t()
        ) :: HTTPoison.Request.t()
  def save_request_to_ets(
        %HTTPoison.Request{} = request,
        from,
        request_data,
        %__MODULE__{requests: requests}
      ) do
    :ets.insert(requests, {request, from: from, request_data: request_data})

    request
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

  def write_to_disk?(
        %__MODULE__{write_responses_to_disk?: false},
        _response
      ),
      do: false

  def write_to_disk?(
        %__MODULE__{write_responses_to_disk?: true, service: service},
        response
      ) do
    service
    |> Service.module()
    |> apply(:successful_response?, [response])
  end

  def data_folder_path(%__MODULE__{data_folder_path: "" <> data_folder_path}) do
    data_folder_path
  end

  defp ensure_data_file_started(%__MODULE__{data_file_instance: pid} = state) when is_pid(pid) do
    state
  end

  defp ensure_data_file_started(%__MODULE__{data_file_instance: module, service: service} = state)
       when is_atom(module) do
    pid =
      case GenServer.start(module,
             data_folder_path: state.data_folder_path,
             data_file_name_fn: &Service.data_file_name(service, &1)
           ) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end

    Map.replace!(state, :data_file_instance, pid)
  end

  defp ensure_throttler_started(name) when is_atom(name) do
    case GenServer.whereis(name) do
      nil -> raise RequestThrottler.NotStartedError.exception(name: name)
      pid -> pid
    end
  end

  defp ensure_throttler_started(pid) when is_pid(pid), do: pid

  @spec get_request_from_ets(t(), RequestThrottler.Response.t()) :: request_ets_item()
  defp get_request_from_ets(
         %__MODULE__{requests: requests},
         %RequestThrottler.Response{request: request}
       ) do
    [{^request, from: from, request_data: request_data}] = :ets.take(requests, request)
    %{from: from, request_data: request_data}
  end

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

  @spec maybe_write_to_disk(
          state :: State.t(),
          response :: Ebird.Recordings.raw_response() | RequestThrottler.Response.t(),
          request :: any()
        ) :: RequestThrottler.Response.t() | Ebird.Recordings.raw_response()
  def maybe_write_to_disk(%__MODULE__{} = state, response, request) do
    if write_to_disk?(state, response) do
      write_to_disk(state, response, request)
    end

    response
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

  @type response() :: {:ok, any()} | {:error, any()}

  @spec parse_and_save_response(t(), response(), ThrottledCache.request_data()) :: response()
  defp parse_and_save_response(%__MODULE__{} = state, response, request_data) do
    parsed = parse_response(state, response, request_data)
    save_response(state, {request_data, parsed})

    parsed
  end

  defp parse_response(%__MODULE__{service: service}, {:ok, json}, request_data) do
    parsed =
      service
      |> Service.response_module()
      |> apply(:parse, [json, request_data])

    {:ok, parsed}
  end

  defp parse_response(%__MODULE__{}, {:error, error}, _) do
    {:error, error}
  end

  defp send_response(
         %__MODULE__{} = state,
         %RequestThrottler.Response{
           response: response
         },
         {request_data, from}
       ) do
    GenServer.reply(
      from,
      parse_and_save_response(state, response, request_data)
    )
  end

  @spec start_ets(t()) :: map
  defp start_ets(%__MODULE__{} = state) do
    state
    |> Map.replace!(:requests, __MODULE__ |> Module.concat(:RequestsETS) |> :ets.new([]))
    |> Map.update!(:supervisors, &do_start_ets(&1, state))
  end

  @spec do_start_ets(Supervisors.t(), t()) :: Supervisors.t()
  defp do_start_ets(%Supervisors{} = supervisors, %__MODULE__{
         ets_name: ets_name,
         ets_opts: ets_opts,
         data_file_instance: data_file_instance,
         listeners: listeners,
         service: service
       }) do
    {:ok, pid} =
      ETS.start_link(
        ets_name: ets_name,
        ets_opts: ets_opts,
        data_file_instance: data_file_instance,
        listeners: listeners,
        service: service
      )

    %{supervisors | ets: pid}
  end

  defp verify_state(
         %__MODULE__{
           base_url: "" <> _,
           service: %Service{module: service_module, whereis: service_pid},
           ets_name: ets_name
         } = state
       )
       when is_known_service(service_module) and is_pid(service_pid) and ets_name !== nil,
       do: state

  @spec write_to_disk(
          t(),
          RequestThrottler.Response.t(),
          TC.request_data()
        ) ::
          :ok | {:error, any()}
  def write_to_disk(
        %__MODULE__{
          data_file_instance: instance,
          service: service
        },
        %RequestThrottler.Response{response: response},
        request
      )
      when is_pid(instance) do
    DataFile.write(
      %DataFile.Data{
        request: request,
        response: response,
        service: service
      },
      instance
    )
  end
end
