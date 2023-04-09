defmodule BirdSong.Services.Ebird.RegionSpeciesCodes do
  use BirdSong.Services.ThrottledCache,
    base_url: "https://api.ebird.org",
    data_folder_path: "",
    ets_opts: [],
    ets_name: :ebird_region_species_codes,
    throttler: BirdSong.Services.RequestThrottler.EbirdAPI

  alias BirdSong.Services.Ebird

  @type request_data() :: {:region_species_codes, String.t()}

  def get_codes("" <> region, server) do
    get({:region_species_codes, region}, server)
  end

  def endpoint({:region_species_codes, region}) do
    Path.join(["v2", "product", "spplist", region])
  end

  def ets_key({:region_species_codes, region}), do: region

  def headers({:region_species_codes, "" <> _}),
    do: [Ebird.token_header() | user_agent()]

  def message_details({:region_species_codes, region}), do: %{region: region}

  def params({:region_species_codes, "" <> _}), do: []

  def parse_from_disk({:region_species_codes, "" <> _region}, _server),
    do: :not_found

  def read_from_disk({:region_species_codes, "" <> region}, _server),
    do: {:error, {:enoent, region}}

  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

  def handle_info(:create_data_folder, state) do
    # region codes will never be written to disk
    {:noreply, state}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
