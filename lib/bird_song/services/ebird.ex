defmodule BirdSong.Services.Ebird do
  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :throttled_cache

  require Logger
  alias BirdSong.Services.Helpers
  alias __MODULE__.Observation

  defmodule Response do
    alias BirdSong.Services.Ebird.Observation

    defstruct observations: []

    @type t() :: %__MODULE__{
            observations: [Observation.t()]
          }

    def parse(observations) when is_list(observations) do
      %__MODULE__{
        observations: Enum.map(observations, &Observation.parse/1)
      }
    end
  end

  def params({:recent_observations, _}), do: [{"back", 30}]

  def headers({:recent_observations, _}), do: [{"x-ebirdapitoken", @token}]

  def message_details({:recent_observations, region}), do: %{region: region}

  def url({:recent_observations, region}) do
    __MODULE__
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["v2/data/obs", region, "recent"])
    |> Path.join()
  end

  @spec get_recent_observations(String.t(), GenServer.server()) ::
          Helpers.api_response(Response.t())
  def get_recent_observations("" <> region, server) do
    get({:recent_observations, region}, server)
  end

  def ets_key({:recent_observations, region}), do: region

  def handle_info(:seed_ets_table, state) do
    {:noreply, state}
  end

  def handle_info(message, state) do
    super(message, state)
  end
end
