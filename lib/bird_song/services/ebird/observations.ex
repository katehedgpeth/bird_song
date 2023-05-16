defmodule BirdSong.Services.Ebird.Observations do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :ebird_observations

  require Logger
  alias BirdSong.{Services.Ebird, Services.Helpers, Services.Worker}

  @type request_data() :: {:recent_observations, String.t()}

  def endpoint({:recent_observations, region}) do
    Path.join(["v2/data/obs", region, "recent"])
  end

  def ets_key({:recent_observations, region}), do: region

  @spec get_recent_observations(String.t(), Worker.t()) ::
          Helpers.api_response(Response.t())
  def get_recent_observations("" <> region, worker) do
    get({:recent_observations, region}, worker)
  end

  def handle_info(:create_data_folder, state) do
    {:noreply, state}
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

  def parse_from_disk({:recent_observations, _region}, _server),
    do: :not_found

  def read_from_disk({:recent_observations, region}, _server),
    do: {:error, {:enoent, region}}
end
