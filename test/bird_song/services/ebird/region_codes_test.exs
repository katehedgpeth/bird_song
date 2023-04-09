defmodule BirdSong.Services.Ebird.RegionSpeciesCodesTest do
  use ExUnit.Case
  import BirdSong.TestSetup

  alias BirdSong.TestHelpers
  alias BirdSong.Services.Ebird.RegionSpeciesCodes
  @region "US-NC-067"

  setup_all do
    {:ok, raw_codes: File.read!("test/mock_data/region_species_codes/" <> @region <> ".json")}
  end

  setup [:start_throttler]

  setup %{bypass: bypass, throttler: throttler} do
    {:ok, service} =
      RegionSpeciesCodes.start_link(base_url: TestHelpers.mock_url(bypass), throttler: throttler)

    {:ok, bypass: bypass, service: service}
  end

  describe "&get/1" do
    test "returns a list of species codes when API returns a successful response", %{
      bypass: bypass,
      raw_codes: raw_codes,
      service: service
    } do
      Bypass.expect(bypass, &success_response(&1, raw_codes))

      assert {:ok, %RegionSpeciesCodes.Response{region: @region, codes: ["bbwduc" | _]}} =
               RegionSpeciesCodes.get({:region_species_codes, @region}, service)
    end
  end

  def success_response(conn, raw_codes) do
    Plug.Conn.resp(conn, 200, raw_codes)
  end
end
