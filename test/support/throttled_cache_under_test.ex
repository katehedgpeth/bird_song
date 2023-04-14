defmodule BirdSong.ThrottledCacheUnderTest do
  defmacro __using__(cache_args) do
    quote location: :keep, bind_quoted: [cache_args: cache_args] do
      use BirdSong.Services.ThrottledCache, cache_args

      defmodule __MODULE__.Response do
        defstruct response: :not_provided

        def parse(response, _) do
          %__MODULE__{response: response}
        end
      end

      def data_file_name({__MODULE__, "" <> arg}) do
        "data_file_name_" <> arg
      end

      def endpoint({__MODULE__, "" <> arg}) do
        Path.join(["endpoint", arg])
      end

      def ets_key({__MODULE__, "" <> arg}), do: "ets_key_" <> arg

      def params({__MODULE__, "" <> arg}), do: %{"param" => arg}

      def headers({__MODULE__, "" <> arg}), do: [{"X-Custom-Header", arg} | user_agent()]
    end
  end
end
