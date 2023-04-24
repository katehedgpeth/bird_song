defmodule BirdSong.Services.RequestThrottler do
  use GenServer
  alias BirdSong.Services.RequestThrottler.ForbiddenExternalURLError
  alias BirdSong.Services.Helpers
  alias __MODULE__.{UrlError, Response}

  @enforce_keys [:base_url]
  defstruct [
    :base_url,
    :current_request,
    :unthrottle_ref,
    # used by MacaulayLibrary
    :scraper,
    queue: [],
    queue_size: 0,
    request_fn: {__MODULE__, :call_httpoison},
    throttled?: false,
    throttle_ms: :timer.seconds(1)
  ]

  @type timers() :: %{
          queued: NaiveDateTime.t(),
          sent: NaiveDateTime.t() | nil,
          responded: NaiveDateTime.t() | nil
        }
  @type queue_item() :: {Request.t(), pid(), timers()}
  @type current_request_info() :: {Task.t(), queue_item()}
  @type response() ::
          {:response, any(), timers()}

  @type t() :: %__MODULE__{
          base_url: URI.t() | {:error, ForbiddenExternalURLError.exception()},
          current_request: current_request_info() | nil,
          queue: :queue.queue(queue_item()),
          queue_size: integer(),
          scraper: atom() | {atom(), pid()} | nil,
          request_fn: {atom(), atom()},
          throttled?: boolean(),
          throttle_ms: integer(),
          unthrottle_ref: reference() | nil
        }

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @doc """
  Add a request to the queue. The response will be sent back to the
  caller using &GenServer.cast/2.

  response: %RequestThrottler.Response{
    response: {:ok, %{"raw" => "decoded_json"}} | {:error, _},
    timers: %{queued: NaiveDateTime, sent: NaiveDateTime, responded: NaiveDateTime},
    request: %HTTPoison.Request{}
  }
  """
  @callback add_to_queue(Request.t(), GenServer.server()) :: :ok
  def add_to_queue(%HTTPoison.Request{url: "/" <> _} = request, server) do
    GenServer.cast(
      server,
      {:add_to_queue,
       {
         request,
         self(),
         %{queued: NaiveDateTime.utc_now(), responded: nil}
       }}
    )
  end

  def add_to_queue(%HTTPoison.Request{url: url}, _server) do
    raise UrlError.exception(url: url)
  end

  @callback base_url(GenServer.server()) :: String.t()
  def base_url(server) do
    GenServer.call(server, :base_url)
  end

  def build_state(opts) do
    opts
    |> parse_base_url()
    |> Keyword.put_new(:queue, :queue.new())
    |> __struct__()
  end

  def get_current_request_url(
        %__MODULE__{
          current_request: {%Task{}, {request, _from, _timers}}
        } = state
      ) do
    state
    |> update_request_url(request)
    |> Map.fetch!(:url)
  end

  @callback parse_response(any(), t()) :: Helpers.api_response()
  def parse_response(response, state),
    do: Helpers.parse_api_response(response, get_current_request_url(state))

  def handle_response(
        response,
        ref,
        %__MODULE__{current_request: {%Task{ref: ref}, request_tuple}} = state
      ) do
    reply(state, response, request_tuple)

    {
      :noreply,
      %{state | current_request: nil},
      {:continue, {:schedule_next_send, state.throttle_ms}}
    }
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  @impl GenServer
  def handle_call(:base_url, _from, %__MODULE__{base_url: base_url} = state) do
    {:reply,
     case base_url do
       %URI{} -> URI.to_string(base_url)
       _ -> base_url
     end, state}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast(
        {:add_to_queue, request_tuple},
        %__MODULE__{base_url: {:error, %ForbiddenExternalURLError{} = error}} = state
      ) do
    reply(state, {:error, error}, request_tuple)
    {:noreply, state}
  end

  def handle_cast(
        {:add_to_queue,
         {
           %HTTPoison.Request{},
           parent,
           %{queued: %NaiveDateTime{}, responded: nil}
         } = item},
        %__MODULE__{} = state
      )
      when is_pid(parent) do
    {:noreply, do_add_to_queue(state, item)}
  end

  @impl GenServer
  def handle_continue({:schedule_next_send, throttle_ms}, %__MODULE__{} = state) do
    {:noreply, schedule_next_send(state, throttle_ms)}
  end

  @impl GenServer
  def handle_info(:send_request, %__MODULE__{queue_size: 0} = state) do
    # queue is empty, so don't actually send a request;
    # schedule another message in 100 milliseconds
    {
      :noreply,
      state,
      {:continue, {:schedule_next_send, 100}}
    }
  end

  def handle_info(
        :send_request,
        %__MODULE__{
          current_request: {%Task{}, _from, %{}}
        } = state
      ) do
    # We are still waiting for a response from the previous request, so do nothing.
    # The next request will be scheduled when the response is received.
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(
        :send_request,
        %__MODULE__{
          current_request: nil,
          queue_size: size
        } = state
      )
      when size > 0 do
    # there is a request in the queue and no outstanding request is being awaited,
    # so send the next request
    {:noreply, send_request(state)}
  end

  def handle_info(
        {ref, response},
        %__MODULE__{} = state
      )
      when is_reference(ref) do
    # this is the response to the request that is being awaited
    response
    |> parse_response(state)
    |> handle_response(ref, state)
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def init(opts) do
    do_init(opts)
  end

  @callback do_init(Keyword.t()) :: {:ok, t(), {:continue, {:schedule_next_send, 0}}}
  def do_init(opts) do
    {:ok, build_state(opts), {:continue, {:schedule_next_send, 0}}}
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  #########################################################
  #########################################################
  ##
  ##  TASK METHOD
  ##
  #########################################################

  def call_httpoison(request, %__MODULE__{}) do
    HTTPoison.request(request)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec cancel_unthrottle_msg(t()) :: t()
  defp cancel_unthrottle_msg(%__MODULE__{unthrottle_ref: nil} = state), do: state

  defp cancel_unthrottle_msg(%__MODULE__{} = state) do
    _ = Process.cancel_timer(state.unthrottle_ref)
    %{state | unthrottle_ref: nil}
  end

  @spec create_throttle_msg(t(), integer()) :: t()
  defp create_throttle_msg(
         %__MODULE__{} = state,
         throttle_ms
       ),
       do: %{state | unthrottle_ref: Process.send_after(self(), :send_request, throttle_ms)}

  @spec do_add_to_queue(t(), queue_item()) :: t()
  defp do_add_to_queue(%__MODULE__{} = state, {request, parent, timers}) do
    %{state | queue: :queue.in({request, parent, timers}, state.queue)}
    |> update_queue_size()
  end

  defp do_update_request_url("" <> path, %URI{} = base_url) do
    base_url
    |> URI.merge(URI.new!(path))
    |> URI.to_string()
  end

  defp get_queue_size(%__MODULE__{queue: queue}) do
    :queue.len(queue)
  end

  @spec log_external_api_call(HTTPoison.Request.t(), timers(), t()) :: :ok
  defp log_external_api_call(%HTTPoison.Request{url: "http://localhost" <> _}, %{}, %__MODULE__{}) do
    :ok
  end

  defp log_external_api_call(
         %HTTPoison.Request{} = request,
         %{queued: queued, sent: sent},
         %__MODULE__{} = state
       ) do
    Helpers.log(
      [
        event: "external_api_call",
        request: request,
        status: "sent",
        queue_size: get_queue_size(state),
        waiting_for: NaiveDateTime.diff(sent, queued, :millisecond)
      ],
      __MODULE__,
      case Mix.env() do
        :test -> :warning
        _ -> :info
      end
    )
  end

  defp parse_base_url(opts) do
    opts
    |> Keyword.replace!(:base_url, opts |> Map.new() |> uri_or_error(Mix.env()))
    |> Keyword.delete(:allow_external_calls?)
  end

  defp reply(%__MODULE__{base_url: base_url}, response, request_tuple) do
    {%HTTPoison.Request{} = request, from, timers} = request_tuple
    timers = Map.replace!(timers, :responded, NaiveDateTime.utc_now())

    url_or_error =
      case base_url do
        %URI{} -> URI.to_string(base_url)
        {:error, _} -> base_url
      end

    GenServer.cast(
      from,
      %Response{
        base_url: url_or_error,
        request: request,
        response: response,
        timers: timers
      }
    )
  end

  defp update_queue_size(%__MODULE__{} = state) do
    %{
      state
      | queue_size: get_queue_size(state)
    }
  end

  defp update_request_url(%__MODULE__{base_url: base_url}, %HTTPoison.Request{} = request) do
    Map.update!(request, :url, &do_update_request_url(&1, base_url))
  end

  @spec uri_or_error(
          %{required(:base_url) => String.t(), optional(:allow_external_calls?) => boolean()},
          :dev | :test | :prod
        ) :: URI.t() | ForbiddenExternalURLError.t()
  defp uri_or_error(%{base_url: "" <> _ = base_url}, env) when env in [:dev, :prod] do
    URI.new!(base_url)
  end

  defp uri_or_error(%{base_url: "http://localhost" <> _ = localhost}, :test) do
    URI.new!(localhost)
  end

  defp uri_or_error(
         %{base_url: "https://" <> _ = external_url, allow_external_calls?: true},
         :test
       ) do
    URI.new!(external_url)
  end

  defp uri_or_error(%{base_url: "" <> _} = opts, :test) do
    {:error, ForbiddenExternalURLError.exception(opts: Keyword.new(opts))}
  end

  @spec schedule_next_send(t(), integer()) :: t()
  defp schedule_next_send(%__MODULE__{} = state, throttle_ms) do
    state
    |> cancel_unthrottle_msg()
    |> create_throttle_msg(throttle_ms)
  end

  @spec send_request(t()) :: t()
  defp send_request(%__MODULE__{request_fn: {mod, func}} = state) do
    {item, state} = take_from_queue(state)
    {%HTTPoison.Request{} = request, from, timers} = item

    timers = Map.put(timers, :sent, NaiveDateTime.utc_now())

    with_updated_url = update_request_url(state, request)
    log_external_api_call(with_updated_url, timers, state)

    task =
      Task.Supervisor.async_nolink(
        __MODULE__.TaskSupervisor,
        mod,
        func,
        [with_updated_url, state]
      )

    %{state | current_request: {task, {request, from, timers}}}
  end

  @spec take_from_queue(t()) :: {queue_item(), t()}
  defp take_from_queue(%__MODULE__{queue: queue, queue_size: size} = state) when size > 0 do
    {{:value, item}, queue} = :queue.out(queue)

    {item, update_queue_size(%{state | queue: queue})}
  end
end
