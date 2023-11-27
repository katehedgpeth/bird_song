defmodule BirdSong.Services.ThrottledCache do
  alias BirdSong.Services.DataFile

  alias BirdSong.{
    Bird,
    Services.Ebird,
    Services.Helpers,
    Services.RequestThrottler,
    Services.Service,
    Services.Worker
  }

  alias __MODULE__.State

  @type request_data() ::
          Bird.t()
          | Ebird.request_data()
  @type response_struct() :: struct()

  @callback build_request(request_data, State.t()) :: HTTPoison.Request.t()
  @callback endpoint(request_data()) :: String.t()
  @callback ets_key(request_data()) :: String.t()
  @callback headers(request_data()) :: HTTPoison.headers()
  @callback params(request_data()) :: HTTPoison.params()
  @callback request_options(request_data()) :: HTTPoison.options()
  @callback message_details(request_data()) :: Map.t()
  @callback response_module() :: module()
  @callback read_from_disk(request_data(), Worker.t()) ::
              {:ok, String.t()} | {:error, {:enoent, String.t()}}
  @callback parse_from_disk(request_data(), Worker.t()) ::
              {:ok, response_struct()} | :not_found

  @callback successful_response?(RequestThrottler.Response.t()) :: boolean()

  @optional_callbacks [response_module: 0]

  @env Application.compile_env(:bird_song, __MODULE__)
  @admin_email Application.compile_env(
                 :bird_song,
                 [__MODULE__, :admin_email],
                 {:error, :admin_email_missing}
               )

  def data_file_name(%Bird{common_name: common_name}) do
    common_name
    |> String.replace(" ", "_")
    |> String.replace("/", "\\")
  end

  @type decoded_json() :: list() | map()
  @spec parse_response(
          State.t() | Worker.t(),
          decoded_json() | {:ok, decoded_json()} | {:error, any()},
          request_data()
        ) :: {:ok, response_struct()} | {:error, any()}
  def parse_response(_, {:error, error}, _) do
    {:error, error}
  end

  def parse_response(%State{} = state, decoded_response, request_data) do
    parse_response(state.worker, decoded_response, request_data)
  end

  def parse_response(%Worker{} = worker, {:ok, decoded_json}, request_data) do
    parse_response(worker, decoded_json, request_data)
  end

  def parse_response(%Worker{} = worker, decoded_json, request_data)
      when is_map(decoded_json) or is_list(decoded_json) do
    parsed =
      worker
      |> Worker.response_module()
      |> apply(:parse, [decoded_json, request_data])

    {:ok, parsed}
  end

  # dialyzer thinks this will only ever match the string
  @dialyzer {:no_match, user_agent: 0}
  def user_agent() do
    case @admin_email do
      {:error, :admin_email_missing} ->
        raise "Admin email is missing!!!"

      "" <> email ->
        [{"User-Agent", "BirdSongBot (#{email})"}]
    end
  end

  defmacro __using__(module_opts) do
    quote location: :keep,
          bind_quoted: [
            module_opts: module_opts,
            env: @env
          ] do
      require Logger
      use Worker, option_keys: State.start_link_option_keys()

      alias BirdSong.{Bird, Services}

      alias Services.ThrottledCache, as: TC

      alias Services.{
        Ebird,
        Helpers,
        ThrottledCache.State,
        Service,
        Worker
      }

      alias __MODULE__.Response

      @overridable [
        build_request: 2,
        data_file_name: 1,
        endpoint: 1,
        ets_key: 1,
        headers: 1,
        params: 1,
        request_options: 1,
        message_details: 1,
        parse_from_disk: 2,
        read_from_disk: 2,
        successful_response?: 1,
        handle_info: 2,
        handle_call: 3
      ]

      @behaviour TC

      @backlog_timeout_ms Keyword.fetch!(env, :backlog_timeout_ms)
      @throttle_ms Keyword.fetch!(env, :throttle_ms)
      @module_opts module_opts

      @spec clear_cache(atom | pid) :: :ok
      def clear_cache(server) do
        GenServer.cast(server, :clear_cache)
      end

      def data_folder_path(%Worker{instance_name: name}) do
        GenServer.call(name, :data_folder_path)
      end

      @spec get(TC.request_data(), Worker.t()) ::
              Helpers.api_response(Response.t())

      def get(data, %Worker{} = worker) do
        with :not_found <- get_from_cache(data, worker),
             :not_found <- parse_from_disk(data, worker) do
          GenServer.call(worker.instance_name, {:get_from_api, data}, :infinity)
        end
      end

      @spec get_from_cache(TC.request_data(), Worker.t()) ::
              {:ok, Response.t()} | :not_found
      def get_from_cache(data, %Worker{instance_name: server}) do
        GenServer.call(server, {:get_from_cache, data})
      end

      @spec has_data?(TC.request_data(), Worker.t()) :: boolean()
      def has_data?(request_data, %Worker{instance_name: server}) do
        GenServer.call(server, {:has_data?, request_data})
      end

      @spec register_request_listener(Worker.t()) :: :ok
      def register_request_listener(%Worker{instance_name: server}) do
        GenServer.cast(server, {:register_request_listener, self()})
      end

      #########################################################
      #########################################################
      ##
      ##  OVERRIDABLE METHODS
      ##
      #########################################################

      @doc """
      Name of the file that will be saved to disk. Name should NOT include
      a .json extension.
      """
      @spec data_file_name(TC.request_data()) :: String.t()
      def data_file_name(%Bird{} = bird) do
        TC.data_file_name(bird)
      end

      def data_file_name({:recent_observations, region}), do: region

      @impl TC
      def endpoint(_), do: raise("ThrottledCache module must define a &endpoint/1 method")

      @impl TC
      def ets_key(%Bird{sci_name: sci_name}), do: sci_name

      @impl TC
      def build_request(request_data, _ \\ %{}) do
        %HTTPoison.Request{
          headers: headers(request_data),
          method: :get,
          params: params(request_data),
          url: Path.join("/", endpoint(request_data)),
          options: request_options(request_data)
        }
      end

      @impl TC
      def headers(%Bird{}), do: user_agent()

      @impl TC
      def message_details(%Bird{} = bird), do: %{bird: bird}

      @impl TC
      def params(%Bird{}), do: []

      @impl TC
      def request_options(_), do: []

      @impl TC
      def read_from_disk(data, %Worker{instance_name: server}),
        do: GenServer.call(server, {:read_from_disk, data})

      @impl TC
      def parse_from_disk(data, %Worker{instance_name: server}),
        do: GenServer.call(server, {:parse_from_disk, data})

      @impl TC
      def successful_response?(%RequestThrottler.Response{response: {:ok, _}}),
        do: true

      def successful_response?(%RequestThrottler.Response{
            response: {:error, _}
          }),
          do: false

      #########################################################
      #########################################################
      ##
      ##  GENSERVER
      ##
      #########################################################

      @impl Worker
      def do_init(opts) do
        {:ok,
         @module_opts
         |> Keyword.merge(opts)
         |> State.new(), {:continue, :create_data_folder}}
      end

      @impl GenServer
      def handle_call(
            {:get_from_api, request_data},
            from,
            %State{} = state
          ) do
        State.notify_listeners(state, request_data, :start)

        :ok = State.add_request_to_queue(state, from: from, request_data: request_data)

        {:noreply, state}
      end

      def handle_call({:get_from_cache, data}, _from, state) do
        {:reply, State.lookup(state, data), state}
      end

      def handle_call({:has_data?, request_data}, _from, %State{ets_table: ets_table} = state) do
        {:reply, :ets.member(ets_table, ets_key(request_data)), state}
      end

      def handle_call(:data_folder_path, _from, %State{} = state) do
        {:reply, State.data_folder_path(state), state}
      end

      def handle_call({:read_from_disk, request}, _from, %State{} = state) do
        {:reply, State.read_from_disk(state, request), state}
      end

      def handle_call({:parse_from_disk, request}, _from, %State{} = state) do
        {:reply, State.parse_from_disk(state, request), state}
      end

      def handle_call(:state, _from, state) do
        {:reply, state, state}
      end

      @impl GenServer
      def handle_cast(
            %RequestThrottler.Response{} = response,
            state
          ) do
        {:noreply, State.handle_response(state, response)}
      end

      def handle_cast({:update_write_config, write_to_disk?}, %State{} = state) do
        {:noreply, State.update_write_config(state, write_to_disk?)}
      end

      def handle_cast(:clear_cache, state) do
        {:noreply, State.clear_cache(state)}
      end

      def handle_cast({:register_request_listener, pid}, state) do
        {:noreply, State.register_request_listener(state, pid)}
      end

      @impl GenServer
      def handle_continue(:create_data_folder, state) do
        _ = DataFile.create_data_folder(state.worker)

        {:noreply, state}
      end

      def handle_continue(message, state) do
        raise RuntimeError.exception(
                message: """

                Unexpected handle_continue message:
                #{inspect(message)}

                state:
                #{inspect(state)}

                """
              )

        {:noreply, state}
      end

      @impl GenServer
      def handle_info({:save, data}, %State{} = state) do
        State.maybe_save_response(state, data)
        {:noreply, state}
      end

      def handle_info({ref, response}, %State{} = state)
          when is_reference(ref) do
        Helpers.log(
          [error: :unexpected_task_response, response: response, ref: ref],
          __MODULE__,
          :warning
        )

        {:noreply, state}
      end

      def handle_info(:unthrottle, %State{} = state) do
        send(self(), :send_request)
        {:noreply, State.unthrottle(state)}
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{} = state) do
        {:noreply, State.forget_task(state, ref)}
      end

      #########################################################
      #########################################################
      ##
      ##  PRIVATE METHODS
      ##
      #########################################################

      defp url(%State{} = state, request_data) do
        state
        |> State.base_url()
        |> Path.join(endpoint(request_data))
      end

      defp user_agent(), do: BirdSong.Services.ThrottledCache.user_agent()

      defoverridable @overridable
    end
  end
end
