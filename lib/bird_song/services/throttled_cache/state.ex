defmodule BirdSong.Services.ThrottledCache.State do
  require Logger

  alias BirdSong.{
    Bird,
    Services,
    Services.ThrottledCache,
    Services.DataFile,
    Services.XenoCanto,
    Services.Flickr,
    Services.Ebird
  }

  @type request_data() :: {GenServer.from(), any()}

  @type t() :: %__MODULE__{
          ets_table: :ets.table(),
          ets_name: atom(),
          ets_opts: [:ets.table_type()],
          backlog: [request_data],
          data_file_instance: GenServer.server(),
          request_listeners: [pid()],
          service: [XenoCanto | Flickr | Ebird],
          tasks: %{reference() => request_data()},
          throttled?: boolean(),
          throttle_ms: integer()
        }

  defstruct [
    :ets_table,
    :ets_name,
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
      |> Keyword.fetch!(:throttle_ms)
  ]

  defguard is_known_service(service)
           when service in [XenoCanto, Flickr, Ebird, ThrottledCacheUnderTest]

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

  @spec send_request(t()) :: t()
  def send_request(%__MODULE__{backlog: []} = state) do
    # ignore message, because there are no requests to send
    state
  end

  def send_request(%__MODULE__{throttled?: true} = state) do
    # do nothing, because requests are currently throttled.
    # :send_request will be called again when requests are unthrottled.
    state
  end

  def send_request(%__MODULE__{throttled?: false} = state) do
    [{from, request_data} | backlog] = Map.fetch!(state, :backlog)
    service = Map.fetch!(state, :service)

    log_request(state, request_data, :start)

    notify_listeners(state, :start, request_data)

    %Task{ref: ref} =
      Task.Supervisor.async(
        Services.Tasks,
        service,
        :get_from_api,
        [request_data, state],
        timeout: :infinity
      )

    state
    |> Map.replace!(:throttled?, true)
    |> Map.replace!(:backlog, backlog)
    |> Map.update!(:tasks, &Map.put(&1, ref, {from, request_data}))
  end

  def save_response(%__MODULE__{} = state, {request_data, {:ok, response}}) do
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

  def unthrottle(%__MODULE__{} = state) do
    Map.replace!(state, :throttled?, false)
  end

  def register_request_listener(%__MODULE__{} = state, pid) do
    Map.update!(state, :request_listeners, &[pid | &1])
  end

  def notify_listeners(
        %__MODULE__{request_listeners: listeners, service: service},
        start_or_end,
        request
      ) do
    Enum.each(
      listeners,
      &send(
        &1,
        build_request_message(start_or_end, request, service)
      )
    )
  end

  defp ets_table(%__MODULE__{ets_table: ets_table}), do: ets_table

  defp ets_key(%__MODULE__{service: service}, request_data),
    do: apply(service, :ets_key, [request_data])

  @spec build_request_message(:start | {:end, any()}, {GenServer.from(), any()}, atom()) ::
          {:start_request | :end_request,
           %{
             optional(:bird) => Bird.t(),
             optional(:response) => any(),
             optional(:region) => String.t(),
             module: atom(),
             time: DateTime.t()
           }}
  defp build_request_message(start_or_end, request, service) do
    {
      message_name(start_or_end),
      service
      |> default_message()
      |> Map.merge(apply(service, :message_details, [request]))
      |> maybe_add_response_to_message(start_or_end)
    }
  end

  defp maybe_add_response_to_message(message, :start) do
    message
  end

  defp maybe_add_response_to_message(message, {:end, response}) do
    Map.put(message, :response, response)
  end

  @spec default_message(atom()) :: %{module: atom(), time: DateTime.t()}
  defp default_message(module) do
    %{
      module: module,
      time: DateTime.now!("Etc/UTC")
    }
  end

  defp message_name(:start), do: :start_request
  defp message_name({:end, _response}), do: :end_request

  defp log_request(%__MODULE__{service: service}, request, start_or_end)
       when start_or_end in [:start, :end] do
    [
      inspect([service]),
      "message=#{start_or_end}_request",
      log_request_details(request)
    ]
    |> Enum.join(" ")
    |> String.trim()
    |> Logger.debug()
  end

  defp log_request_details({:recent_observations, region}), do: "region=" <> region
  defp log_request_details(%Bird{common_name: common_name}), do: "bird=" <> common_name

  defp verify_state(%__MODULE__{service: service, ets_name: ets_name} = state)
       when is_known_service(service) and ets_name !== nil,
       do: {:ok, state}
end
