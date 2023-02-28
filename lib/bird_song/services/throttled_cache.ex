defmodule BirdSong.Services.ThrottledCache do
  alias BirdSong.Services.Helpers

  @callback get_from_api(Bird.t()) :: Helpers.api_response(any())
  @env Application.compile_env!(:bird_song, __MODULE__)

  defmacro __using__(ets_opts: ets_opts, ets_name: ets_name) do
    quote do
      require Logger
      use GenServer
      alias BirdSong.{Bird, Services}
      alias Services.Helpers

      defstruct [:ets_table, throttled?: false, backlog: [], tasks: %{}, request_listeners: []]

      @backlog_timeout_ms unquote(@env) |> Keyword.fetch!(:backlog_timeout_ms)

      @throttle_ms unquote(@env) |> Keyword.fetch!(:throttle_ms)

      @spec get(Bird.t(), pid() | atom) :: {:ok, any} | :not_found
      def get(%Bird{} = bird, server) do
        case get_from_cache(bird, server) do
          {:ok, data} ->
            {:ok, data}

          :not_found ->
            GenServer.call(server, {:get_from_api, bird}, @backlog_timeout_ms)
        end
      end

      @spec get_from_cache(Bird.t(), pid | atom) :: {:ok, Response.t()} | :not_found
      def get_from_cache(%Bird{} = bird, nil) do
        raise "SERVER CANNOT BE NIL!!!"
      end

      def get_from_cache(%Bird{} = bird, server) do
        GenServer.call(server, {:get_from_cache, bird})
      end

      @spec clear_cache(atom | pid) :: :ok
      def clear_cache(server) do
        GenServer.cast(server, :clear_cache)
      end

      def has_data?(%Bird{} = bird, server) do
        GenServer.call(server, {:has_data?, bird})
      end

      def register_request_listener(server) do
        GenServer.cast(server, {:register_request_listener, self()})
      end

      #########################################################
      #########################################################
      ##
      ##  GENSERVER
      ##
      #########################################################

      def start_link(opts) do
        GenServer.start_link(__MODULE__, :ok, name: Keyword.get(opts, :name, __MODULE__))
      end

      def init(:ok) do
        {:ok, %__MODULE__{ets_table: start_table()}}
      end

      def handle_call(
            {:get_from_api, %Bird{} = bird},
            from,
            %__MODULE__{} = state
          ) do
        send(self(), :send_request)

        {:noreply,
         %{
           state
           | backlog:
               state
               |> Map.fetch!(:backlog)
               |> Enum.reverse([{from, bird}])
               |> Enum.reverse()
         }}
      end

      def handle_call({:get_from_cache, %Bird{sci_name: bird}}, _from, %__MODULE__{} = state) do
        result =
          case :ets.lookup(state.ets_table, bird) do
            [{^bird, response}] -> {:ok, response}
            [] -> :not_found
          end

        {:reply, result, state}
      end

      def handle_call({:has_data?, %Bird{sci_name: sci_name}}, _from, %__MODULE__{} = state) do
        {:reply, :ets.member(state.ets_table, sci_name), state}
      end

      def handle_cast(:clear_cache, %__MODULE__{} = state) do
        :ets.delete(state.ets_table)
        {:noreply, %{state | ets_table: start_table()}}
      end

      def handle_cast({:register_request_listener, pid}, %__MODULE__{} = state) do
        {:noreply, %{state | request_listeners: [pid | state.request_listeners]}}
      end

      def handle_info(:send_request, %__MODULE__{backlog: []} = state) do
        # ignore message, because there are no requests to send
        {:noreply, state}
      end

      def handle_info(:send_request, %__MODULE__{throttled?: true} = state) do
        # do nothing, because requests are currently throttled.
        # :send_request will be called again when requests are unthrottled.
        {:noreply, state}
      end

      def handle_info(
            :send_request,
            %__MODULE__{
              throttled?: false,
              backlog: [{from, %Bird{} = bird} | backlog]
            } = state
          ) do
        Logger.debug(
          "message=sending_request module=#{inspect(__MODULE__)} bird=" <> bird.common_name
        )

        Enum.each(
          state.request_listeners,
          &send(
            &1,
            {:start_request,
             %{
               module: __MODULE__,
               bird: bird,
               time: DateTime.now!("Etc/UTC")
             }}
          )
        )

        %Task{ref: ref} = Task.Supervisor.async(Services, __MODULE__, :get_from_api, [bird])

        updated_state = %{
          state
          | throttled?: true,
            backlog: backlog,
            tasks: Map.put(state.tasks, ref, {from, bird})
        }

        {:noreply, updated_state}
      end

      def handle_info({:save, {%Bird{sci_name: id}, {:ok, response}}}, %__MODULE__{} = state) do
        :ets.insert(state.ets_table, {id, response})
        {:noreply, state}
      end

      def handle_info({:save, {%Bird{}, {:error, _}}}, %__MODULE__{} = state) do
        # don't save error responses
        {:noreply, state}
      end

      def handle_info({ref, response}, %__MODULE__{} = state)
          when is_reference(ref) do
        state
        |> Map.fetch!(:tasks)
        |> Map.fetch!(ref)
        |> handle_response(response, state)

        {:noreply, state}
      end

      def handle_info(:unthrottle, %__MODULE__{} = state) do
        send(self(), :send_request)
        {:noreply, %{state | throttled?: false}}
      end

      def handle_info({:DOWN, ref, :process, _pid, _reason}, %__MODULE__{} = state) do
        {_, tasks} = Map.pop!(state.tasks, ref)
        {:noreply, %{state | tasks: tasks}}
      end

      #########################################################
      #########################################################
      ##
      ##  PRIVATE METHODS
      ##
      #########################################################

      defp start_table() do
        :ets.new(unquote(ets_name), unquote(ets_opts))
      end

      defp handle_response({from, %Bird{} = bird}, response, %__MODULE__{
             request_listeners: listeners
           }) do
        send(self(), {:save, {bird, response}})

        Enum.each(
          listeners,
          &send(
            &1,
            {:end_request,
             %{
               module: __MODULE__,
               bird: bird,
               time: DateTime.now!("Etc/UTC"),
               response: response
             }}
          )
        )

        Process.send_after(self(), :unthrottle, @throttle_ms)

        GenServer.reply(from, response)
      end
    end
  end
end
