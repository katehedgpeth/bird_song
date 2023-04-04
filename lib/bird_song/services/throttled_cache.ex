defmodule BirdSong.Services.ThrottledCache do
  alias BirdSong.Services.DataFile
  alias BirdSong.Services.Helpers

  @type request_data() :: Bird.t() | {:recent_observations, String.t()}

  @callback endpoint(request_data()) :: String.t()
  @callback ets_key(request_data()) :: String.t()
  @callback headers(request_data()) :: HTTPoison.headers()
  @callback params(request_data()) :: HTTPoison.params()
  @callback message_details(request_data()) :: Map.t()

  @env Application.compile_env!(:bird_song, __MODULE__)

  @admin_email Application.compile_env!(:bird_song, :admin_email)

  def user_agent(headers) do
    [{"User-Agent", "BirdSongBot (#{@admin_email})"} | headers]
  end

  defmacro __using__(module_opts) do
    quote location: :keep,
          bind_quoted: [
            module_opts: module_opts,
            env: @env
          ] do
      @behaviour BirdSong.Services.ThrottledCache
      require Logger
      use GenServer
      alias BirdSong.{Bird, Services}

      alias Services.{
        Ebird,
        Helpers,
        ThrottledCache,
        ThrottledCache.State,
        Service
      }

      alias __MODULE__.Response

      @backlog_timeout_ms Keyword.fetch!(env, :backlog_timeout_ms)
      @throttle_ms Keyword.fetch!(env, :throttle_ms)
      @module_opts module_opts

      @type request_data() :: Services.ThrottledCache.request_data()

      @spec get(request_data(), Service.t() | GenServer.server()) ::
              Helpers.api_response(Response.t())
      def get(data, %Service{whereis: pid}) do
        get(data, pid)
      end

      def get(data, server) when is_pid(server) or is_atom(server) do
        case get_from_cache(data, server) do
          {:ok, data} ->
            {:ok, data}

          :not_found ->
            GenServer.call(server, {:get_from_api, data}, :infinity)
        end
      end

      @spec get_from_cache(request_data(), GenServer.server()) ::
              {:ok, Response.t()} | :not_found
      def get_from_cache(_data, nil) do
        raise "SERVER CANNOT BE NIL!!!"
      end

      def get_from_cache(data, server) do
        GenServer.call(server, {:get_from_cache, data})
      end

      @spec clear_cache(atom | pid) :: :ok
      def clear_cache(server) do
        GenServer.cast(server, :clear_cache)
      end

      @spec has_data?(request_data(), GenServer.server()) :: boolean()
      def has_data?(request_data, server) do
        GenServer.call(server, {:has_data?, request_data})
      end

      @spec register_request_listener(GenServer.server()) :: :ok
      def register_request_listener(server) do
        GenServer.cast(server, {:register_request_listener, self()})
      end

      def parse_response(response, request, state) do
        response
        |> Helpers.parse_api_response(url(state, request))
        |> case do
          {:ok, raw} ->
            {:ok, Response.parse(raw)}

          {:error, error} ->
            {:error, error}
        end
      end

      def data_folder_path(%Service{whereis: pid}) when is_pid(pid) do
        GenServer.call(pid, :data_folder_path)
      end

      def data_folder_path(%Service{module: module} = service) do
        case GenServer.whereis(module) do
          nil ->
            raise Service.NotStartedError.exception(module: module)

          pid ->
            data_folder_path(%{service | whereis: pid})
        end
      end

      #########################################################
      #########################################################
      ##
      ##  OVERRIDABLE METHODS
      ##
      #########################################################

      @spec endpoint(request_data()) :: String.t()
      def endpoint(_) do
        raise("ThrottledCache module must define a &endpoint/1 method")
      end

      defoverridable(endpoint: 1)

      @spec get_from_api(request_data(), State.t()) :: {:ok, Response.t()} | Helpers.api_error()
      def get_from_api(request, %State{} = state) do
        state
        |> url(request)
        |> log_external_api_call()
        |> HTTPoison.get(
          headers(request),
          params: params(request)
        )
        |> log_external_api_response(request, state)
        |> maybe_write_to_disk(request, state)
        |> parse_response(request, state)
      end

      defoverridable(get_from_api: 2)

      @spec headers(request_data()) :: HTTPoison.headers()
      def headers(%Bird{}), do: []

      @spec params(request_data()) :: HTTPoison.params()
      def params(%Bird{}), do: []
      defoverridable(params: 1)

      @spec ets_key(any()) :: String.t()
      def ets_key(%Bird{sci_name: sci_name}), do: sci_name
      defoverridable(ets_key: 1)

      @spec message_details(request_data()) :: Map.t()
      def message_details(%Bird{} = bird), do: %{bird: bird}
      defoverridable(message_details: 1)

      @spec write_to_disk({:ok, HTTPoison.Response.t() | [Map.t()]}, request_data(), State.t()) ::
              :ok | {:error, any()}
      def write_to_disk({:ok, _} = response, request, %State{
            data_file_instance: instance,
            service: service
          }) do
        DataFile.write(
          %DataFile.Data{
            request: request,
            response: response,
            service: service
          },
          instance
        )
      end

      defoverridable(write_to_disk: 3)

      @spec data_file_name(request_data()) :: String.t()
      def data_file_name(%Bird{common_name: common_name}) do
        common_name
        |> String.replace(" ", "_")
        |> String.replace("/", "\\")
      end

      def data_file_name({:recent_observations, region}), do: region
      defoverridable(data_file_name: 1)

      def seed_ets_table(%State{} = state) do
        State.seed_ets_table(state)
      end

      def successful_response?({:ok, %HTTPoison.Response{status_code: 200}}), do: true
      def successful_response?({:ok, %HTTPoison.Response{}}), do: false
      def successful_response?({:error, %HTTPoison.Error{}}), do: false
      defoverridable(successful_response?: 1)

      #########################################################
      #########################################################
      ##
      ##  GENSERVER
      ##
      #########################################################

      def start_link(opts) do
        {name, opts} =
          @module_opts
          |> Keyword.merge(opts)
          |> Keyword.put_new(:throttle_ms, @throttle_ms)
          |> Keyword.pop(:name, __MODULE__)

        GenServer.start_link(__MODULE__, opts, name: name)
      end

      def init(opts) do
        send(self(), :create_data_folder)

        {:ok,
         opts
         |> Keyword.put(:service, %Service{module: __MODULE__, whereis: self()})
         |> State.new()}
      end

      def handle_call(
            {:get_from_api, request_data},
            from,
            %State{} = state
          ) do
        send(self(), :send_request)

        {:noreply, State.add_request_to_backlog(state, from, request_data)}
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

      def handle_call(
            {:parse_response, request: request, response: response},
            _from,
            %State{} = state
          ) do
        {:reply, parse_response(response, request, state), state}
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

      def handle_info(:seed_ets_table, state) do
        {:noreply, seed_ets_table(state)}
      end

      def handle_info(:create_data_folder, state) do
        :ok =
          state
          |> State.data_folder_path()
          |> File.mkdir_p()

        {:noreply, state}
      end

      def handle_info(
            :send_request,
            %State{} = state
          ) do
        state = if State.should_send_request?(state), do: State.send_request(state), else: state
        {:noreply, state}
      end

      def handle_info({:save, data}, %State{} = state) do
        State.save_response(state, data)
        {:noreply, state}
      end

      def handle_info(
            {ref, {:ok, %{__struct__: __MODULE__.Response}} = response},
            %State{} = state
          )
          when is_reference(ref) do
        handle_task_response(state, ref, response)
      end

      def handle_info({ref, {:error, {:no_results, request}} = response}, %State{} = state)
          when is_reference(ref) do
        Helpers.log([error: :no_results, request: request], __MODULE__, :warning)
        handle_task_response(state, ref, response)
      end

      def handle_info({ref, {:error, {:not_found, _}} = response}, %State{} = state)
          when is_reference(ref) do
        handle_task_response(state, ref, response)
      end

      def handle_info({ref, {:error, {:bad_response, _}} = response}, %State{} = state)
          when is_reference(ref) do
        handle_task_response(state, ref, response)
      end

      def handle_info({ref, {:error, {:timeout, _}} = response}, %State{} = state)
          when is_reference(ref) do
        handle_task_response(state, ref, response)
      end

      def handle_info({ref, {:error, %HTTPoison.Error{}} = response}, %State{} = state)
          when is_reference(ref) do
        handle_task_response(state, ref, response)
      end

      def handle_info(:unthrottle, %State{} = state) do
        send(self(), :send_request)
        {:noreply, State.unthrottle(state)}
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{} = state) do
        {:noreply, State.forget_task(state, ref)}
      end

      defoverridable(handle_info: 2)
      defoverridable(handle_call: 3)

      #########################################################
      #########################################################
      ##
      ##  PRIVATE METHODS
      ##
      #########################################################

      defp handle_task_response(%State{tasks: tasks} = state, ref, response) do
        tasks
        |> Map.fetch!(ref)
        |> do_handle_task_response(response, state)

        {:noreply, state}
      end

      defp do_handle_task_response({:seed_data_task, request}, response, %State{}) do
        :ok
      end

      defp do_handle_task_response(
             {{pid, ref} = from, request_data},
             response,
             %State{throttle_ms: throttle_ms} = state
           )
           when is_pid(pid) and is_reference(ref) do
        send(self(), {:save, {request_data, response}})

        State.notify_listeners(state, request_data, {:end, response})

        Process.send_after(self(), :unthrottle, throttle_ms)

        GenServer.reply(from, response)
      end

      @spec log_external_api_call(String.t()) :: String.t()
      defp log_external_api_call("http://localhost" <> _ = url) do
        url
      end

      defp log_external_api_call("" <> url) do
        Helpers.log(
          [event: "external_api_call", url: url, status: "sent"],
          __MODULE__,
          case Mix.env() do
            :test -> :warning
            _ -> :info
          end
        )

        url
      end

      defp log_external_api_response(
             response,
             request,
             state
           ) do
        case url(state, request) do
          "http://localhost" <> _ -> :ok
          url -> do_log_external_api_response(url, response)
        end

        response
      end

      defp do_log_external_api_response(url, response) do
        {level, details} =
          case response do
            {:ok, %HTTPoison.Response{status_code: 200}} ->
              {:info, status_code: 200}

            {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
              {:error, status_code: code, body: body}

            {:error, %HTTPoison.Error{} = error} ->
              {:error, error: error}
          end

        [
          {:event, "external_api_call"},
          {:url, url} | details
        ]
        |> Helpers.log(__MODULE__, level)
      end

      defp response_status({:ok, %HTTPoison.Response{status_code: 200}}), do: {:debug, "success"}

      defp url(%State{base_url: "" <> base_url}, request_data) do
        Path.join(base_url, endpoint(request_data))
      end

      defp user_agent(), do: [{"User-Agent", "BirdSongBot (#{@admin_email})"}]

      @spec maybe_write_to_disk(
              response :: Ebird.Recordings.raw_response() | Helpers.api_response(Response.t()),
              request :: any(),
              state :: State.t()
            ) :: Helpers.api_response(Response.t()) | Ebird.Recordings.raw_response()
      defp maybe_write_to_disk(response, request, %State{} = state) do
        if successful_response?(response) and State.write_to_disk?(state) do
          write_to_disk(response, request, state)
        end

        response
      end
    end
  end
end
