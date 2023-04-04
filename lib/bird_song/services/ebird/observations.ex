defmodule BirdSong.Services.Ebird.Observations do
  use BirdSong.Services.ThrottledCache,
    base_url: BirdSong.Services.Ebird.base_url(),
    data_folder_path: "data/observations/ebird",
    ets_opts: [],
    ets_name: :throttled_cache

  require Logger
  alias BirdSong.{Services.Ebird, Services.Helpers}

  @type request_data() :: {:recent_observations, String.t()}

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
    do: [Ebird.token_header() | user_agent()]

  def headers({:recent_observations, _region}), do: headers()

  def message_details({:recent_observations, region}), do: %{region: region}

  def params({:recent_observations, _}), do: [{"back", 30}]
end
