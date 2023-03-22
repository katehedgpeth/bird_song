defmodule BirdSong.Services.Ebird.Recordings.Playwright do
  use GenServer

  alias BirdSong.{
    Bird,
    Services.Ebird.Recordings,
    Services.ThrottledCache,
    Services.Helpers
  }

  @throttle_ms :bird_song
               |> Application.compile_env!(ThrottledCache)
               |> Keyword.fetch!(:throttle_ms)

  defstruct [
    :base_url,
    :bird,
    :error,
    :parent,
    :port,
    :reply_to,
    current_request_number: 0,
    ready?: false,
    responses: [],
    throttle_ms: @throttle_ms
  ]

  @type t() :: %__MODULE__{
          base_url: String.t(),
          bird: Bird.t(),
          current_request_number: integer(),
          error: {:error, any()} | nil,
          parent: pid(),
          port: port() | nil,
          ready?: boolean(),
          reply_to: GenServer.from(),
          responses: [Map.t()],
          throttle_ms: integer()
        }

  @runner_script :bird_song
                 |> :code.priv_dir()
                 |> Path.join("static/assets/playwright_runner.js")

  @auth_json :bird_song
             |> :code.priv_dir()
             |> Path.join("static/assets/playwright_auth.json")

  @node_path System.find_executable("node")

  @max_requests 3

  def run(whereis) do
    GenServer.call(whereis, :run)
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
    {:ok, open_port(state)}
  end

  def handle_info({port, {:data, message}}, %__MODULE__{port: port} = state) do
    {:noreply, receive_message(message, state)}
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

  def handle_info({:DOWN, _, :port, port, :normal}, %__MODULE__{port: port} = state) do
    {:noreply, %{state | port: nil, ready?: false}}
  end

  def handle_call(:run, from, %__MODULE__{} = state) do
    send(self(), :send_request)
    {:noreply, %{state | reply_to: from}}
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

  defp get_initial_cursor_mark(%__MODULE__{current_request_number: 1}) do
    nil
  end

  defp get_initial_cursor_mark(%__MODULE__{responses: [%{"cursorMark" => "" <> cursor_mark} | _]}) do
    cursor_mark
  end

  defp init_state(opts) do
    struct(
      __MODULE__,
      opts
      |> Keyword.put_new(:parent, self())
      |> Keyword.put_new(:base_url, Recordings.base_url())
      |> Keyword.put_new(
        :throttle_ms,
        Helpers.get_env(ThrottledCache, :throttle_ms)
      )
    )
  end

  defp log_external_api_call(%__MODULE__{base_url: "http://localhost" <> _}) do
    :ok
  end

  defp log_external_api_call(%__MODULE__{base_url: url}) do
    Helpers.log(%{message: "external_api_call", url: url}, __MODULE__, :warning)
  end

  defp notify_parent(%__MODULE__{parent: parent}, message) do
    send(parent, {__MODULE__, DateTime.now!("Etc/UTC"), message})
  end

  def open_port(%__MODULE__{base_url: base_url} = state) do
    log_external_api_call(state)

    port =
      Port.open({:spawn_executable, @node_path}, [
        :binary,
        :stderr_to_stdout,
        args: [
          @runner_script,
          base_url,
          @auth_json
        ]
      ])

    Port.monitor(port)
    Port.command(port, "connect")
    %{state | port: port}
  end

  @spec receive_message(String.t(), t()) :: t()
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
      {:ok, recordings} ->
        recordings
        |> add_recordings_to_state(state)
        |> send_again_or_reply_and_close()

      {:error, _} ->
        receive_message(message, state)
    end
  end

  defp do_receive_message(message, %__MODULE__{} = state) do
    state
    |> Map.replace!(:error, {:error, UnknownMessageError, data: message})
    |> reply_and_close()
  end

  defp reply(%__MODULE__{reply_to: from, responses: [_ | _] = responses} = state) do
    GenServer.reply(
      from,
      {:ok, Enum.reverse(responses)}
    )

    %{state | reply_to: nil, responses: [], current_request_number: 0}
  end

  defp reply(%__MODULE__{reply_to: from, error: {:error, error}}) do
    GenServer.reply(from, {:error, error})
  end

  defp reply_and_close(%__MODULE__{} = state) do
    true = shutdown_runner(state)

    reply(state)
  end

  defp send_again_or_reply_and_close(%__MODULE__{current_request_number: count} = state)
       when count === @max_requests do
    reply_and_close(state)
  end

  defp send_again_or_reply_and_close(%__MODULE__{throttle_ms: throttle_ms} = state) do
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
    notify_parent(
      state,
      {:request, Map.take(state, [:current_request_number, :bird, :responses])}
    )

    %Bird{species_code: code} = Map.fetch!(state, :bird)

    {state,
     Port.command(
       port,
       Jason.encode!(%{
         code: code,
         initial_cursor_mark: get_initial_cursor_mark(state),
         call_count: count
       })
     )}
  end

  defp shutdown_runner(%__MODULE__{port: port}) do
    # JS script shuts itself down with process.exit()
    Port.command(port, "shutdown")
  end
end
