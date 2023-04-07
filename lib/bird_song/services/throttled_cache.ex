defmodule BirdSong.Services.ThrottledCache do
  alias BirdSong.{
    Bird,
    Services.Ebird,
    Services.DataFile,
    Services.Helpers
  }

  @type request_data() ::
          Bird.t() | Ebird.Observations.request_data() | Ebird.RegionCodes.request_data()

  @callback endpoint(request_data()) :: String.t()
  @callback ets_key(request_data()) :: String.t()
  @callback headers(request_data()) :: HTTPoison.headers()
  @callback params(request_data()) :: HTTPoison.params()
  @callback message_details(request_data()) :: Map.t()

  @env Application.compile_env!(:bird_song, __MODULE__)

  def data_file_name(%Bird{common_name: common_name}) do
    common_name
    |> String.replace(" ", "_")
    |> String.replace("/", "\\")
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

      alias Services.ThrottledCache, as: TC

      alias Services.{
        Ebird,
        Helpers,
        ThrottledCache.State,
        Service
      }

      alias __MODULE__.Response

      @admin_email Application.compile_env!(:bird_song, :admin_email)
      @backlog_timeout_ms Keyword.fetch!(env, :backlog_timeout_ms)
      @throttle_ms Keyword.fetch!(env, :throttle_ms)
      @module_opts module_opts

      @spec clear_cache(atom | pid) :: :ok
      def clear_cache(server) do
        GenServer.cast(server, :clear_cache)
      end

      def data_file_instance(%Service{whereis: pid}) do
        GenServer.call(pid, :data_file_instance)
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

      @spec get(TC.request_data(), Service.t() | GenServer.server()) ::
              Helpers.api_response(Response.t())
      def get(data, %Service{whereis: pid}) do
        get(data, pid)
      end

      def get(data, server) when is_pid(server) or is_atom(server) do
        with :not_found <- get_from_cache(data, server),
             :not_found <- parse_from_disk(data, server) do
          GenServer.call(server, {:get_from_api, data}, :infinity)
        end
      end

      @spec get_from_cache(TC.request_data(), GenServer.server()) ::
              {:ok, Response.t()} | :not_found
      def get_from_cache(_data, nil) do
        raise "SERVER CANNOT BE NIL!!!"
      end

      def get_from_cache(data, server) do
        GenServer.call(server, {:get_from_cache, data})
      end

      @spec has_data?(TC.request_data(), GenServer.server()) :: boolean()
      def has_data?(request_data, server) do
        GenServer.call(server, {:has_data?, request_data})
      end

      def parse_response(response, request, state) do
        response
        |> Helpers.parse_api_response(url(state, request))
        |> case do
          {:ok, raw} ->
            {:ok, Response.parse(raw, request)}

          {:error, error} ->
            {:error, error}
        end
      end

      @spec register_request_listener(GenServer.server()) :: :ok
      def register_request_listener(server) do
        GenServer.cast(server, {:register_request_listener, self()})
      end

      #########################################################
      #########################################################
      ##
      ##  OVERRIDABLE METHODS
      ##
      #########################################################

      @spec data_file_name(TC.request_data()) :: String.t()
      def data_file_name(%Bird{} = bird) do
        TC.data_file_name(bird)
      end

      def data_file_name({:recent_observations, region}), do: region
      defoverridable(data_file_name: 1)

      @spec endpoint(TC.request_data()) :: String.t()
      def endpoint(_), do: raise("ThrottledCache module must define a &endpoint/1 method")
      defoverridable(endpoint: 1)

      @spec ets_key(any()) :: String.t()
      def ets_key(%Bird{sci_name: sci_name}), do: sci_name
      defoverridable(ets_key: 1)

      @spec get_from_api(TC.request_data(), State.t()) ::
              {:ok, Response.t()} | Helpers.api_error()
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

      @spec headers(TC.request_data()) :: HTTPoison.headers()
      def headers(%Bird{}), do: user_agent()
      defoverridable(headers: 1)

      @spec message_details(TC.request_data()) :: Map.t()
      def message_details(%Bird{} = bird), do: %{bird: bird}
      defoverridable(message_details: 1)

      @spec params(TC.request_data()) :: HTTPoison.params()
      def params(%Bird{}), do: []
      defoverridable(params: 1)

      @spec read_from_disk(TC.request_data(), GenServer.server()) ::
              {:ok, String.t()} | {:error, {:enoent, String.t()}}
      def read_from_disk(data, server), do: GenServer.call(server, {:read_from_disk, data})
      defoverridable(read_from_disk: 2)

      @spec parse_from_disk(TC.request_data(), GenServer.server()) ::
              {:ok, Response.t()} | :not_found
      def parse_from_disk(data, server), do: GenServer.call(server, {:parse_from_disk, data})
      defoverridable(parse_from_disk: 2)

      def successful_response?({:ok, %HTTPoison.Response{status_code: 200}}), do: true
      def successful_response?({:ok, %HTTPoison.Response{}}), do: false
      def successful_response?({:error, %HTTPoison.Error{}}), do: false
      defoverridable(successful_response?: 1)

      @spec write_to_disk({:ok, HTTPoison.Response.t() | [Map.t()]}, TC.request_data(), State.t()) ::
              :ok | {:error, any()}
      def write_to_disk({:ok, _} = response, request, %State{
            data_file_instance: instance,
            service: service
          })
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

      def write_to_disk(_, _, %State{data_file_instance: instance}) when is_pid(instance) do
        {:error, :bad_response}
      end

      def write_to_disk(_, _, %State{data_file_instance: instance}) do
        {:error, {:not_alive, instance}}
      end

      defoverridable(write_to_disk: 3)

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

      def handle_call(:data_file_instance, _from, %State{} = state) do
        {:reply, state.data_file_instance, state}
      end

      def handle_call(
            {:parse_response, request: request, response: response},
            _from,
            %State{} = state
          ) do
        {:reply, parse_response(response, request, state), state}
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

      def handle_cast({:update_write_config, write_to_disk?}, %State{} = state) do
        {:noreply, State.update_write_config(state, write_to_disk?)}
      end

      def handle_cast(:clear_cache, state) do
        {:noreply, State.clear_cache(state)}
      end

      def handle_cast({:register_request_listener, pid}, state) do
        {:noreply, State.register_request_listener(state, pid)}
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

      defp url(%State{base_url: "" <> base_url}, request_data) do
        Path.join(base_url, endpoint(request_data))
      end

      defp user_agent(), do: [{"User-Agent", "BirdSongBot (#{@admin_email})"}]
    end
  end
end
