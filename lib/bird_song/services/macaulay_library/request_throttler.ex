defmodule BirdSong.Services.MacaulayLibrary.RequestThrottler do
  use GenServer
  alias BirdSong.Services.RequestThrottler
  @behaviour RequestThrottler

  #########################################################
  #########################################################
  ##
  ##  CALLBACKS
  ##
  #########################################################

  @impl RequestThrottler
  def add_to_queue(request, server), do: RequestThrottler.add_to_queue(request, server)

  @impl RequestThrottler
  def base_url(server), do: RequestThrottler.base_url(server)

  @impl RequestThrottler
  def parse_response(response, _state) do
    response
  end

  #########################################################
  #########################################################
  ##
  ##  TASK METHOD
  ##
  #########################################################

  def call_scraper(request, %RequestThrottler{scraper: {scraper_module, scraper_pid}}) do
    scraper_module.run(scraper_pid, request)
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  @spec init(keyword) :: {:ok, any, {:continue, {:schedule_next_send, 0}}}
  def init(opts) do
    do_init(opts)
  end

  @impl RequestThrottler
  def do_init(opts) do
    {:ok, build_state(opts), {:continue, {:schedule_next_send, 0}}}
  end

  @impl GenServer
  def handle_call(msg, from, state) do
    RequestThrottler.handle_call(msg, from, state)
  end

  @impl GenServer
  def handle_cast(msg, state) do
    RequestThrottler.handle_cast(msg, state)
  end

  @impl GenServer
  def handle_continue(msg, state) do
    RequestThrottler.handle_continue(msg, state)
  end

  @impl GenServer

  def handle_info({ref, response}, state) do
    RequestThrottler.handle_response(response, ref, state)
  end

  def handle_info(msg, state) do
    RequestThrottler.handle_info(msg, state)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp build_state(opts) do
    opts
    |> Keyword.put_new(:throttle_ms, 2_000)
    |> Keyword.put(:request_fn, {__MODULE__, :call_scraper})
    |> start_scraper_instance(Keyword.fetch!(opts, :scraper))
    |> RequestThrottler.build_state()
  end

  defp start_scraper_instance(opts, module) when is_atom(module) and module !== nil do
    {:ok, pid} =
      opts
      |> Keyword.take([:base_url, :throttle_ms])
      |> module.start_link()

    Keyword.put(opts, :scraper, {module, pid})
  end

  defp start_scraper_instance(opts, {module, pid}) when is_atom(module) and is_pid(pid) do
    opts
  end
end
