defmodule BirdSong.Services.ThrottledCache do
  alias BirdSong.Services.Helpers

  @type request_data() :: Bird.t() | {:recent_observations, String.t()}

  @callback url(request_data()) :: String.t()
  @callback ets_key(request_data()) :: String.t()
  @callback headers(request_data()) :: HTTPoison.headers()
  @callback params(request_data()) :: HTTPoison.params()
  @callback message_details(request_data()) :: Map.t()

  @env Application.compile_env!(:bird_song, __MODULE__)

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
      alias Services.{Helpers, ThrottledCache.State}
      alias __MODULE__.Response

      @backlog_timeout_ms Keyword.fetch!(env, :backlog_timeout_ms)
      @throttle_ms Keyword.fetch!(env, :throttle_ms)
      @module_opts module_opts

      @type request_data() :: Services.ThrottledCache.request_data()

      @spec get(request_data(), GenServer.server()) ::
              {:ok, any} | :not_found
      def get(data, server) do
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

      # unfortunately it seems that this has to be public in order
      # for it to be called as a task in the :send_request call.
      @spec get_from_api(request_data(), State.t()) :: Helpers.api_response(Response.t())
      def get_from_api(request, %State{} = state) do
        request
        |> url()
        |> log_external_api_call()
        |> HTTPoison.get(headers(request), params: params(request))
        |> maybe_write_to_disk(state)
        |> Helpers.parse_api_response()
        |> case do
          {:ok, raw} ->
            {:ok, Response.parse(raw)}

          {:error, error} ->
            {:error, error}
        end
      end

      #########################################################
      #########################################################
      ##
      ##  OVERRIDABLE METHODS
      ##
      #########################################################

      @spec url(request_data) :: String.t()
      def url(_), do: raise("ThrottledCache module must define a &url/1 method")

      @spec headers(request_data()) :: HTTPoison.headers()
      def headers(%Bird{}), do: []

      @spec params(request_data()) :: HTTPoison.params()
      def params(%Bird{}), do: []

      @spec ets_key(any()) :: String.t()
      def ets_key(%Bird{sci_name: sci_name}), do: sci_name

      @spec message_details(request_data()) :: Map.t()
      def message_details(%Bird{} = bird), do: %{bird: bird}

      defoverridable(headers: 1)
      defoverridable(params: 1)
      defoverridable(ets_key: 1)
      defoverridable(message_details: 1)
      defoverridable(url: 1)

      #########################################################
      #########################################################
      ##
      ##  GENSERVER
      ##
      #########################################################

      def start_link(opts) do
        {name, opts} =
          opts
          |> Keyword.merge(@module_opts)
          |> Keyword.put(:service, __MODULE__)
          |> Keyword.put_new(:throttle_ms, @throttle_ms)
          |> Keyword.pop(:name, __MODULE__)

        GenServer.start_link(__MODULE__, opts, name: name)
      end

      def init(opts) do
        {:ok, State.new(opts)}
      end

      def handle_call(
            {:get_from_api, request_data},
            from,
            %State{} = state
          ) do
        send(self(), :send_request)

        {:noreply,
         %{
           state
           | backlog:
               state
               |> Map.fetch!(:backlog)
               |> Enum.reverse([{from, request_data}])
               |> Enum.reverse()
         }}
      end

      def handle_call({:get_from_cache, data}, _from, state) do
        {:reply, State.lookup(state, data), state}
      end

      def handle_call({:has_data?, request_data}, _from, %State{ets_table: ets_table} = state) do
        {:reply, :ets.member(ets_table, ets_key(request_data)), state}
      end

      def handle_cast(:clear_cache, state) do
        {:noreply, State.clear_cache(state)}
      end

      def handle_cast({:register_request_listener, pid}, state) do
        {:noreply, State.register_request_listener(state, pid)}
      end

      def handle_info(
            :send_request,
            %State{} = state
          ) do
        {:noreply, State.send_request(state)}
      end

      def handle_info({:save, data}, %State{} = state) do
        State.save_response(state, data)
        {:noreply, state}
      end

      def handle_info({ref, response}, %State{} = state)
          when is_reference(ref) do
        state
        |> Map.fetch!(:tasks)
        |> Map.fetch!(ref)
        |> handle_response(response, state)

        {:noreply, state}
      end

      def handle_info(:unthrottle, %State{} = state) do
        send(self(), :send_request)
        {:noreply, State.unthrottle(state)}
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, %State{} = state) do
        {_, tasks} = Map.pop!(state.tasks, ref)
        {:noreply, %{state | tasks: tasks}}
      end

      #########################################################
      #########################################################
      ##
      ##  PRIVATE METHODS
      ##
      #########################################################

      defp handle_response(
             {from, request_data},
             response,
             %State{throttle_ms: throttle_ms} = state
           ) do
        send(self(), {:save, {request_data, response}})

        State.notify_listeners(state, {:end, response}, request_data)

        Process.send_after(self(), :unthrottle, throttle_ms)

        GenServer.reply(from, response)
      end

      defp maybe_write_to_disk(response, %State{}) do
        # Ignore for now. Plan to refactor later to save responses as JSON files to use as test mocks.
        response
      end

      @spec log_external_api_call(String.t()) :: String.t()
      defp log_external_api_call("" <> url) do
        case Mix.env() do
          :test -> log_external_api_call(url, :test)
          _ -> url
        end
      end

      @spec log_external_api_call(String.t(), atom()) :: String.t()
      defp log_external_api_call("http://localhost" <> _ = url, :test) do
        url
      end

      defp log_external_api_call("" <> url, :test) do
        [inspect([__MODULE__]), "event=external_api_call", "url=" <> url]
        |> Enum.join(" ")
        |> Logger.warn()

        url
      end
    end
  end
end
