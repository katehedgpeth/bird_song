defmodule BirdSong.Services.Ebird.RegionCodes do
  use BirdSong.Services.ThrottledCache,
    base_url: "https://api.ebird.org",
    data_folder_path: "",
    ets_opts: [],
    ets_name: :ebird_region_codes

  alias BirdSong.Services.Ebird

  @type request_data() :: {:region_codes, String.t()}

  def endpoint({:region_codes, region}) do
    Path.join(["v2", "product", "spplist", region])
  end

  def ets_key({:region_codes, region}), do: region

  def headers({:region_codes, "" <> _}), do: Ebird.headers()

  def params({:region_codes, "" <> _}), do: []

  def handle_info(:create_data_folder, state) do
    # region codes will never be written to disk
    {:noreply, state}
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
