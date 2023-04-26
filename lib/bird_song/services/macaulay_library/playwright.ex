defmodule BirdSong.Services.MacaulayLibrary.Playwright do
  use GenServer

  alias BirdSong.{
    Data.Scraper.BadResponseError,
    Data.Scraper.ConnectionError,
    Data.Scraper.JsonParseError,
    Data.Scraper.TimeoutError,
    Data.Scraper.UnknownMessageError,
    Services.ThrottledCache,
    Services.Helpers
  }

  @behaviour BirdSong.Data.Scraper

  @throttle_ms :bird_song
               |> Application.compile_env!(ThrottledCache)
               |> Keyword.fetch!(:throttle_ms)

  @default_timeout :bird_song
                   |> Application.compile_env!(__MODULE__)
                   |> Keyword.fetch!(:default_timeout)

  @runner_script :bird_song
                 |> :code.priv_dir()
                 |> Path.join("static/assets/playwright_runner.js")

  @node_path System.find_executable("node")

  @max_requests 3

  @enforce_keys [:base_url]

  defstruct [
    :base_url,
    :error,
    :port,
    :reply_to,
    :request,
    current_request_number: 0,
    listeners: [],
    ready?: false,
    responses: [],
    throttle_ms: @throttle_ms,
    timeout: @default_timeout
  ]

  @type t() :: %__MODULE__{
          base_url: String.t(),
          current_request_number: integer(),
          error: {:error, any()} | nil,
          listeners: [pid()],
          port: port() | nil,
          ready?: boolean(),
          reply_to: GenServer.from(),
          request: HTTPoison.Request.t() | nil,
          responses: [Map.t()],
          throttle_ms: integer(),
          timeout: integer()
        }

  @spec run(GenServer.server(), HTTPoison.Request.t()) :: BirdSong.Data.Scraper.response()
  def run(
        whereis,
        %HTTPoison.Request{params: %{"taxonCode" => _}} = request,
        timeout \\ :infinity
      ) do
    GenServer.call(whereis, {:run, request}, timeout)
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      init_state(opts)
    )
  end

  def init(%__MODULE__{} = state) do
    Process.flag(:trap_exit, true)
    {:ok, open_port(state)}
  end

  def handle_info({port, {:data, message}}, %__MODULE__{port: port} = state) do
    with %__MODULE__{} = state <- receive_message(message, state) do
      {:noreply, state}
    end
  end

  def handle_info(:open_port, %__MODULE__{port: nil, ready?: false} = state) do
    {:noreply, open_port(state)}
  end

  def handle_info(:send_request, %__MODULE__{ready?: false} = state) do
    Process.send_after(self(), :send_request, 100)
    {:noreply, state}
  end

  def handle_info(
        :send_request,
        %__MODULE__{current_request_number: count, ready?: true} = state
      )
      when count < @max_requests do
    {:noreply, send_request(state)}
  end

  def handle_info(
        {:DOWN, _, :port, _port, :normal},
        %__MODULE__{} = state
      ) do
    {:noreply, %{state | port: nil, ready?: false}}
  end

  def handle_info({:EXIT, _port, :normal}, %__MODULE__{} = state) do
    {:noreply, %{state | port: nil, ready?: false}}
  end

  def handle_cast(:shutdown_port, %__MODULE__{} = state) do
    {:noreply, shutdown_port(state, {:handle_cast, :shutdown_port})}
  end

  def handle_call({:run, request}, from, %__MODULE__{request: nil} = state) do
    send(self(), :send_request)
    {:noreply, %{state | request: request, reply_to: from}}
  end

  def handle_call(:state, _from, %__MODULE__{} = state) do
    {:reply, state, state}
  end

  def terminate(reason, %__MODULE__{} = state) do
    shutdown_port(state, {:terminate, reason})
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp add_recordings_to_state([_ | _] = new_recordings, %__MODULE__{} = state) do
    Map.update!(
      state,
      :responses,
      fn existing_recordings ->
        Enum.reduce(new_recordings, existing_recordings, &[&1 | &2])
      end
    )
  end

  defp encode_request(%HTTPoison.Request{} = request) do
    request
    |> Map.from_struct()
    |> Map.update!(:headers, &Enum.into(&1, %{}))
  end

  defp ensure_throttled_ms(nil), do: Helpers.get_env(ThrottledCache, :throttle_ms)
  defp ensure_throttled_ms(throttled_ms) when is_integer(throttled_ms), do: throttled_ms

  defp get_initial_cursor_mark(%__MODULE__{current_request_number: 1}) do
    nil
  end

  defp get_initial_cursor_mark(%__MODULE__{responses: [%{"cursorMark" => "" <> cursor_mark} | _]}) do
    cursor_mark
  end

  defp init_state(opts) do
    opts
    |> Keyword.update!(:base_url, & &1)
    |> Keyword.update!(
      :throttle_ms,
      &ensure_throttled_ms/1
    )
    |> __struct__()
  end

  defp log_external_api_call(%__MODULE__{base_url: "http://localhost" <> _}) do
    :ok
  end

  defp log_external_api_call(%__MODULE__{base_url: url}) do
    Helpers.log(%{message: "external_api_call", url: url}, __MODULE__, :info)
  end

  defp notify_listeners(%__MODULE__{listeners: listeners}, message) do
    Enum.each(listeners, &send(&1, {__MODULE__, DateTime.now!("Etc/UTC"), message}))
  end

  defp open_port(%__MODULE__{base_url: base_url, timeout: timeout} = state) do
    port =
      Port.open({:spawn_executable, @node_path}, [
        :binary,
        :stderr_to_stdout,
        args: [@runner_script, base_url, to_string(timeout)]
      ])

    Port.monitor(port)
    Port.command(port, "connect")
    Helpers.log([message: "port_started", port: port, base_url: base_url], __MODULE__, :warning)
    %{state | port: port}
  end

  defp parse_error_message(%{"error" => "timeout", "message" => js_message}, %__MODULE__{}) do
    TimeoutError.exception(timeout_message: js_message)
  end

  defp parse_error_message(
         %{
           "error" => "bad_response",
           "status" => status,
           "response_body" => response_body,
           "url" => url
         },
         %__MODULE__{}
       ) do
    BadResponseError.exception(status: status, response_body: response_body, url: url)
  end

  defp parse_error_message(
         %{
           "error" => "json_parse_error",
           "input" => input,
           "message" => js_message
         },
         %__MODULE__{}
       ) do
    JsonParseError.exception(input: input, error_message: js_message)
  end

  defp parse_error_message(
         %{
           "error" => "unable_to_connect",
           "message" => js_message
         },
         %__MODULE__{base_url: base_url}
       ) do
    ConnectionError.exception(base_url: base_url, js_message: js_message)
  end

  @spec receive_message(String.t(), t()) :: t() | {:stop, :connection_error, t()}
  defp receive_message(message, state) do
    message
    |> String.trim()
    |> do_receive_message(state)
  end

  defp do_receive_message("message=ready_for_requests", %__MODULE__{} = state) do
    %{state | ready?: true}
  end

  defp do_receive_message("message=" <> message, %__MODULE__{} = state) do
    case Jason.decode(message) do
      {:ok, %{"error" => _} = error} ->
        error
        |> parse_error_message(state)
        |> handle_error(state)

      {:ok, []} ->
        reply(state)

      {:ok, [_ | _] = recordings} ->
        recordings
        |> add_recordings_to_state(state)
        |> send_again_or_reply()

      {:error, _} ->
        receive_message(message, state)
    end
  end

  defp do_receive_message(message, %__MODULE__{} = state) do
    [data: message]
    |> UnknownMessageError.exception()
    |> handle_error(state)
  end

  defp handle_error(%ConnectionError{} = error, %__MODULE__{throttle_ms: throttle_ms} = state) do
    # ConnectionError is triggered when the site won't load at all in the initial
    # attempt to setup the port.
    # This should really only happen when ExUnit starts up BirdSong.Application, which
    # starts the real Playwright process that is not meant to be used by tests.
    # That process has a bogus base_url in the test environment, to ensure that we are not
    # hitting https://search.macaulaylibrary.org every time we run a test.
    Process.send_after(self(), :open_port, throttle_ms * 10)

    %{state | error: {:error, error}}
    |> shutdown_port({:connection_error, error})
    |> reply()
  end

  defp handle_error(error, %__MODULE__{reply_to: nil}) do
    raise error
  end

  defp handle_error(error, %__MODULE__{} = state) do
    state
    |> Map.replace!(:error, {:error, error})
    |> reply()
  end

  defp reply(%__MODULE__{reply_to: nil} = state) do
    state
  end

  defp reply(%__MODULE__{error: {:error, _} = error} = state) do
    do_reply(state, error)
  end

  defp reply(%__MODULE__{responses: responses} = state) do
    do_reply(state, {:ok, Enum.reverse(responses)})
  end

  defp do_reply(%__MODULE__{reply_to: from} = state, reply) do
    GenServer.reply(from, reply)

    %{state | request: nil, reply_to: nil, responses: [], current_request_number: 0}
  end

  defp send_again_or_reply(%__MODULE__{current_request_number: count} = state)
       when count === @max_requests do
    reply(state)
  end

  defp send_again_or_reply(%__MODULE__{throttle_ms: throttle_ms} = state) do
    Process.send_after(self(), :send_request, throttle_ms)
    state
  end

  defp send_request(%__MODULE__{} = state) do
    state
    |> Map.update!(:current_request_number, &(&1 + 1))
    |> do_send_request()
    |> elem(0)
  end

  defp do_send_request(%__MODULE__{port: port, current_request_number: count} = state) do
    log_external_api_call(state)

    notify_listeners(
      state,
      {:request, Map.take(state, [:current_request_number, :request, :responses])}
    )

    {state,
     Port.command(
       port,
       Jason.encode!(%{
         call_count: count,
         request: state |> update_params() |> encode_request()
       })
     )}
  end

  @spec shutdown_port(t(), any()) :: t()
  defp shutdown_port(
         %__MODULE__{
           port: port,
           base_url: base_url
         } = state,
         reason
       ) do
    case Port.info(port) do
      nil ->
        :ok

      _ ->
        Helpers.log(
          [
            message: "shutting_down_port",
            reason: reason,
            base_url: base_url,
            port: port
          ],
          __MODULE__,
          :warning
        )

        # JS script shuts itself down with process.exit()
        Port.command(port, "shutdown")
    end

    state
  end

  defp update_params(%__MODULE__{request: request} = state) do
    %HTTPoison.Request{params: params} = request

    %{
      request
      | params:
          case get_initial_cursor_mark(state) do
            nil -> params
            mark -> Map.put(params, :initialCursorMark, mark)
          end
    }
  end
end
