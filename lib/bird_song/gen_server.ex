defmodule BirdSong.GenServer do
  defmacro __using__(module_opts) do
    quote location: :keep, bind_quoted: [module_opts: module_opts] do
      use GenServer

      @module_opts module_opts

      def init(opts), do: {:ok, build_state(opts)}

      def start_link(opts) do
        {name, opts} =
          @module_opts
          |> Keyword.merge(opts)
          |> Keyword.pop(:keep_name_opt?, false)
          |> case do
            {true, merged} ->
              {Keyword.get(merged, :name), merged}

            {false, merged} ->
              Keyword.pop(opts, :name)
          end

        GenServer.start_link(
          __MODULE__,
          opts,
          name: name
        )
      end

      defp build_state(opts) do
        struct(__MODULE__, opts)
      end

      defoverridable(
        init: 1,
        start_link: 1,
        build_state: 1
      )
    end
  end
end
