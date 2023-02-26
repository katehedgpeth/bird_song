defmodule BirdSong.Services.ThrottledCache do
  defmacro __using__(ets_name: ets_name) do
    quote do
      require Logger
      use GenServer
      alias BirdSong.Services
      alias Services.Helpers

      defstruct [:ets_table, throttled?: false, backlog: [], tasks: %{}]

      @api_timeout Application.compile_env!(:bird_song, :throttled_backlog_timeout_ms)

      @spec get(String.t(), pid() | atom) :: {:ok, Recording.t()} | :not_found
      def get(bird, server) do
        case get_from_cache(bird, server) do
          {:ok, recording} ->
            {:ok, recording}

          :not_found ->
            GenServer.call(server, {:get_recording_from_api, bird}, @api_timeout)
        end
      end

      @spec get_from_cache(String.t(), pid | atom) :: {:ok, Response.t()} | :not_found
      def get_from_cache(bird, server) do
        GenServer.call(server, {:get_from_cache, bird})
      end

      @spec clear_cache(atom | pid) :: :ok
      def clear_cache(server) do
        GenServer.cast(server, :clear_cache)
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
            {:get_recording_from_api, bird},
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

      def handle_call({:get_from_cache, bird}, _from, %__MODULE__{} = state) do
        result =
          case :ets.lookup(state.ets_table, bird) do
            [{^bird, response}] -> {:ok, response}
            [] -> :not_found
          end

        {:reply, result, state}
      end

      def handle_cast({:save, {bird, recording}}, %__MODULE__{} = state) do
        :ets.insert(state.ets_table, {bird, recording})
        {:noreply, state}
      end

      def handle_cast(:clear_cache, %__MODULE__{} = state) do
        :ets.delete(state.ets_table)
        {:noreply, %{state | ets_table: start_table()}}
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
              backlog: [{from, "" <> bird} | backlog]
            } = state
          ) do
        %Task{ref: ref} =
          Task.Supervisor.async(Services, __MODULE__, :get_recording_from_api, [bird, self()])

        updated_state = %{
          state
          | throttled?: true,
            backlog: backlog,
            tasks: Map.put(state.tasks, ref, from)
        }

        {:noreply, updated_state}
      end

      def handle_info({ref, response}, %__MODULE__{} = state)
          when is_reference(ref) do
        from = Map.fetch!(state.tasks, ref)

        GenServer.reply(from, response)
        Process.send_after(self(), :unthrottle, Helpers.get_env(:xeno_canto, :throttle_ms))

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
        :ets.new(unquote(ets_name), [])
      end
    end
  end
end
