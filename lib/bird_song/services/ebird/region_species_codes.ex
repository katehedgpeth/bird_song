defmodule BirdSong.Services.Ebird.RegionSpeciesCodes do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :ebird_region_species_codes

  alias BirdSong.{
    Services.Ebird,
    Services.Helpers,
    Services.Worker,
    Services.ThrottledCache
  }

  @type request_data() :: {:region_species_codes, String.t()}

  @spec get_codes(BirdSong.Region.t(), Worker.t()) ::
          {:ok, __MODULE__.Response.t()} | Helpers.api_error()
  def get_codes(%BirdSong.Region{code: region_code}, worker) do
    get_codes(region_code, worker)
  end

  def get_codes("" <> region_code, worker) do
    get({:region_species_codes, region_code}, worker)
  end

  @impl ThrottledCache
  def endpoint({:region_species_codes, region}) do
    Path.join(["v2", "product", "spplist", region])
  end

  @impl ThrottledCache
  def ets_key({:region_species_codes, region}), do: region

  @impl ThrottledCache
  def headers({:region_species_codes, "" <> _}),
    do: [Ebird.token_header() | user_agent()]

  @impl ThrottledCache
  def message_details({:region_species_codes, region}), do: %{region: region}

  @impl ThrottledCache
  def params({:region_species_codes, "" <> _}), do: []

  @impl ThrottledCache
  def parse_from_disk({:region_species_codes, "" <> _region}, _server),
    do: :not_found

  @impl ThrottledCache
  def read_from_disk({:region_species_codes, "" <> region}, _server),
    do: {:error, {:enoent, region}}

  @impl GenServer
  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

  @impl GenServer
  def handle_info(:create_data_folder, state) do
    # region codes will never be written to disk
    {:noreply, state}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
