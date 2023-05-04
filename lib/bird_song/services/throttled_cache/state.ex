defmodule BirdSong.Services.ThrottledCache.State.Supervisors do
  defstruct [:ets]

  @type t() :: %__MODULE__{
          ets: GenServer.server()
        }
end

defmodule BirdSong.Services.ThrottledCache.State do
  require Logger
  require BirdSong.Services.Worker

  alias BirdSong.Services.RequestThrottler

  alias BirdSong.{
    Bird,
    Services.DataFile,
    Services.Helpers,
    Services.ThrottledCache,
    Services.ThrottledCache.State.Supervisors,
    Services.ThrottledCache.ETS,
    Services.Worker
  }

  @type request_ets_item() :: %{
          from: GenServer.from(),
          request_data: ThrottledCache.request_data()
        }

  @type t() :: %__MODULE__{
          ets_table: :ets.table(),
          ets_name: atom(),
          ets_opts: [:ets.table_type()],
          listeners: [pid()],
          requests_ets: :ets.table(),
          # scraper: atom() | {atom(), pid()},
          supervisors: Supervisors.t(),
          write_responses_to_disk?: boolean(),
          worker: Worker.t()
        }

  @enforce_keys [:worker]
  defstruct [
    :ets_table,
    :ets_name,
    :requests_ets,
    # :scraper,
    # :throttler,
    :worker,
    ets_opts: [],
    # backlog: [],
    listeners: [],
    supervisors: %__MODULE__.Supervisors{},
    # throttled?: false,
    write_responses_to_disk?: false
  ]

  def start_link_option_keys() do
    [:listeners, :write_responses_to_disk?]
  end

  @spec add_request_to_queue(BirdSong.Services.ThrottledCache.State.t(), any) :: :ok
  def add_request_to_queue(%__MODULE__{} = state, options) do
    %{from: from, request_data: request_data} = Map.new(options)

    request = apply(state.worker.module, :build_request, [request_data, state])
    :ok = save_request_to_ets(request, from, request_data, state)

    RequestThrottler.add_to_queue(request, get_throttler_name(state))
  end

  @spec base_url(BirdSong.Services.ThrottledCache.State.t()) :: any
  def base_url(%__MODULE__{} = state) do
    state
    |> get_throttler_name()
    |> RequestThrottler.base_url()
  end

  def new(opts) do
    opts
    |> __struct__()
    |> verify_state()
    |> start_ets()
  end

  @spec clear_cache(t()) :: t()
  def clear_cache(%__MODULE__{supervisors: %Supervisors{ets: ets}} = state) do
    ETS.clear_cache(ets)

    state
  end

  def get_throttler_name(%__MODULE__{} = state) do
    Worker.get_sibling(state.worker, :RequestThrottler)
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

  # @spec should_send_request?(t()) :: boolean
  # def should_send_request?(%__MODULE__{backlog: []}) do
  #   # no, because there are no requests to send
  #   false
  # end

  # def should_send_request?(%__MODULE__{throttled?: true}) do
  #   # no, because requests are currently throttled.
  #   # :send_request will be called again when requests are unthrottled.
  #   false
  # end

  # def should_send_request?(%__MODULE__{throttled?: false}) do
  #   # requests are not throttled and the backlog is not empty,
  #   # so we can send the next request.
  #   true
  # end

  def side_effects(%__MODULE__{} = state, {:request, data}) do
    log_request(state, data, :start)
    notify_listeners(state, data, :start)
  end

  @spec maybe_save_response(t(), {ThrottledCache.request_data(), response :: any()}) :: :ok
  def maybe_save_response(
        %__MODULE__{supervisors: %Supervisors{ets: pid}},
        {request_data, response}
      ) do
    ETS.maybe_save_response({request_data, response}, pid)
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
        %__MODULE__{} = state,
        request,
        start_or_end
      ) do
    Enum.each(
      state.listeners,
      &send(
        &1,
        build_request_message(start_or_end, request, state.worker)
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
        ) :: :ok
  def save_request_to_ets(
        %HTTPoison.Request{} = request,
        from,
        request_data,
        %__MODULE__{requests_ets: requests}
      ) do
    case :ets.insert(requests, {request, from: from, request_data: request_data}) do
      true -> :ok
    end
  end

  def update_write_config(%__MODULE__{} = state, write_to_disk?) do
    Map.replace!(state, :write_responses_to_disk?, write_to_disk?)
  end

  def write_to_disk?(
        %__MODULE__{write_responses_to_disk?: false},
        _response
      ),
      do: false

  def write_to_disk?(
        %__MODULE__{write_responses_to_disk?: true, worker: worker},
        response
      ) do
    apply(worker.module, :successful_response?, [response])
  end

  def data_folder_path(%__MODULE__{worker: worker}) do
    Worker.full_data_folder_path(worker)
  end

  @spec get_request_from_ets(t(), RequestThrottler.Response.t()) :: request_ets_item()
  defp get_request_from_ets(
         %__MODULE__{requests_ets: requests},
         %RequestThrottler.Response{request: request}
       ) do
    [{^request, from: from, request_data: request_data}] = :ets.take(requests, request)
    %{from: from, request_data: request_data}
  end

  @spec build_request_message(:start | {:end, any()}, {GenServer.from(), any()}, Worker.t()) ::
          {:start_request | :end_request,
           %{
             optional(:bird) => Bird.t(),
             optional(:response) => any(),
             optional(:region) => String.t(),
             module: atom(),
             time: DateTime.t()
           }}
  defp build_request_message(start_or_end, request, %Worker{} = worker) do
    details = apply(worker.module, :message_details, [request])

    {
      message_name(start_or_end),
      worker
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
          response ::
            MacaulayLibrary.RequestThrottler.raw_response() | RequestThrottler.Response.t(),
          request :: any()
        ) :: RequestThrottler.Response.t() | MacaulayLibrary.RequestThrottler.raw_response()
  def maybe_write_to_disk(%__MODULE__{} = state, response, request) do
    if write_to_disk?(state, response) do
      write_to_disk(state, response, request)
    end

    response
  end

  @spec default_message(Worker.t()) :: %{module: atom(), time: DateTime.t()}
  defp default_message(%Worker{module: module}) do
    %{
      module: module,
      time: DateTime.now!("Etc/UTC")
    }
  end

  defp message_name(:start), do: :start_request
  defp message_name({:end, _response}), do: :end_request

  defp log_request(%__MODULE__{worker: %Worker{module: module}}, request, start_or_end)
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

  defp send_response(
         %__MODULE__{} = state,
         %RequestThrottler.Response{
           response: response
         },
         {request_data, from}
       ) do
    parsed = ThrottledCache.parse_response(state, response, request_data)
    _ = maybe_save_response(state, {request_data, parsed})

    GenServer.reply(
      from,
      parsed
    )
  end

  @spec start_ets(t()) :: map
  defp start_ets(%__MODULE__{} = state) do
    state
    |> Map.replace!(:requests_ets, __MODULE__ |> Module.concat(:RequestsETS) |> :ets.new([]))
    |> Map.update!(:supervisors, &do_start_ets(&1, state))
  end

  @spec do_start_ets(Supervisors.t(), t()) :: Supervisors.t()
  defp do_start_ets(%Supervisors{} = supervisors, %__MODULE__{
         ets_name: ets_name,
         ets_opts: ets_opts,
         listeners: listeners,
         worker: worker
       }) do
    {:ok, pid} =
      ETS.start_link(
        ets_name: ets_name,
        ets_opts: ets_opts,
        listeners: listeners,
        worker: worker
      )

    %{supervisors | ets: pid}
  end

  defp verify_state(
         %__MODULE__{
           worker: %Worker{},
           ets_name: ets_name
         } = state
       )
       when ets_name !== nil,
       do: state

  @spec write_to_disk(
          t(),
          RequestThrottler.Response.t(),
          TC.request_data()
        ) ::
          :ok | {:error, any()}
  def write_to_disk(
        %__MODULE__{
          worker: worker
        },
        %RequestThrottler.Response{response: response},
        request
      ) do
    DataFile.write(%DataFile.Data{
      request: request,
      response: response,
      worker: worker
    })
  end
end
