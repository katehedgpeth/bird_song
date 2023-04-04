defmodule BirdSong.Services.Ebird do
  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  use BirdSong.Services.ThrottledCache,
    base_url: "https://api.ebird.org",
    data_folder_path: "data/observations/ebird",
    ets_opts: [],
    ets_name: :throttled_cache

  require Logger
  alias BirdSong.Services.Helpers
  alias __MODULE__.Observation

  @type request_data() :: {:recent_observations, String.t()}

  defmodule Response do
    alias BirdSong.Services.Ebird.Observation

    defstruct [:region, observations: []]

    @type t() :: %__MODULE__{
            observations: [Observation.t()],
            region: String.t()
          }

    def parse(observations, {:recent_observations, region}) when is_list(observations) do
      %__MODULE__{
        observations: Enum.map(observations, &Observation.parse/1),
        region: region
      }
    end
  end

  def endpoint({:recent_observations, region}) do
    Path.join(["v2/data/obs", region, "recent"])
  end

  def ets_key({:recent_observations, region}), do: region

  @spec get_recent_observations(String.t(), GenServer.server()) ::
          Helpers.api_response(Response.t())
  def get_recent_observations("" <> region, server) do
    get({:recent_observations, region}, server)
  end

  def handle_info(:seed_ets_table, state) do
    {:noreply, state}
  end

  def handle_info(message, state) do
    super(message, state)
  end

  def headers(),
    do: Enum.concat(token_header(), user_agent())

  def headers({:recent_observations, _region}), do: headers()

  def message_details({:recent_observations, region}), do: %{region: region}

  def params({:recent_observations, _}), do: [{"back", 30}]

  def token_header() do
    [{"x-ebirdapitoken", @token}]
  end
end
