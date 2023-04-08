defmodule BirdSong.Services.RequestThrottler.UrlError do
  defexception [:url]

  def message(%__MODULE__{url: url}) do
    """
    Expected url to be a path starting with "/", but got: #{url}
    """
  end
end

defmodule BirdSong.Services.RequestThrottler do
  use GenServer
  alias BirdSong.Services.Helpers
  alias HTTPoison.Request
  alias __MODULE__.UrlError

  @enforce_keys [:base_url]
  defstruct [
    :base_url,
    :current_request,
    :unthrottle_ref,
    queue: [],
    queue_size: 0,
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
          base_url: URI.t(),
          current_request: current_request_info() | nil,
          queue: :queue.queue(queue_item()),
          queue_size: integer(),
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

  def add_to_queue(%Request{url: "/" <> _} = request, server) do
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

  def add_to_queue(%Request{url: url}, _server) do
    raise UrlError.exception(url: url)
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  @impl GenServer
  def handle_cast(
        {:add_to_queue,
         {
           %Request{} = request,
           parent,
           %{queued: %NaiveDateTime{}, responded: nil} = timers
         }},
        %__MODULE__{} = state
      )
      when is_pid(parent) do
    item = {update_request_url(state, request), parent, timers}
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
        %__MODULE__{current_request: {%Task{ref: ref}, {request, from, timers}}} = state
      ) do
    # this is the response to the request that is being awaited
    timers = Map.replace!(timers, :responded, NaiveDateTime.utc_now())

    GenServer.cast(
      from,
      {:response, Helpers.parse_api_response(response, request.url), timers}
    )

    {
      :noreply,
      %{state | current_request: nil},
      {:continue, {:schedule_next_send, state.throttle_ms}}
    }
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def init(opts) do
    {:ok, build_state(opts), {:continue, {:schedule_next_send, 0}}}
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

  defp build_state(opts) do
    opts
    |> Keyword.update!(:base_url, &URI.new!/1)
    |> Keyword.put_new(:queue, :queue.new())
    |> __struct__()
  end

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
    state
    |> Map.update!(:queue, &:queue.in({request, parent, timers}, &1))
    |> Map.update!(:queue_size, &(&1 + 1))
  end

  defp do_update_request_url("" <> path, %URI{} = base_url) do
    base_url
    |> URI.merge(URI.new!(path))
    |> URI.to_string()
  end

  defp update_request_url(%__MODULE__{base_url: base_url}, %Request{} = request) do
    Map.update!(request, :url, &do_update_request_url(&1, base_url))
  end

  @spec schedule_next_send(t(), integer()) :: t()
  defp schedule_next_send(%__MODULE__{} = state, throttle_ms) do
    state
    |> cancel_unthrottle_msg()
    |> create_throttle_msg(throttle_ms)
  end

  @spec send_request(t()) :: t()
  defp send_request(%__MODULE__{} = state) do
    {item, state} = take_from_queue(state)
    {%Request{} = request, from, timers} = item

    task =
      Task.Supervisor.async_nolink(
        __MODULE__.TaskSupervisor,
        HTTPoison,
        :request,
        [request]
      )

    item = {request, from, Map.put(timers, :sent, NaiveDateTime.utc_now())}

    %{state | current_request: {task, item}}
  end

  @spec take_from_queue(t()) :: {queue_item(), t()}
  def take_from_queue(%__MODULE__{queue: queue, queue_size: size} = state) when size > 0 do
    {{:value, item}, queue} = :queue.out(queue)

    {item, %{state | queue: queue, queue_size: size - 1}}
  end
end
