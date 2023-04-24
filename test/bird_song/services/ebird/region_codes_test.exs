defmodule BirdSong.Services.Ebird.RegionSpeciesCodesTest do
  use BirdSong.TestSetup, [:setup_bypass, :start_service_supervisor!]

  alias BirdSong.Services.{
    Ebird,
    Ebird.RegionSpeciesCodes,
    TestSetup
  }

  @moduletag service: :Ebird

  @region "US-NC-067"

  setup_all do
    {:ok, raw_codes: File.read!("test/mock_data/region_species_codes/" <> @region <> ".json")}
  end

  describe "&get/1" do
    test "returns a list of species codes when API returns a successful response", %{
      bypass: bypass,
      raw_codes: raw_codes,
      test: test
    } do
      service = Ebird.get_instance_child(test, :RegionSpeciesCodes)
      Bypass.expect(bypass, &success_response(&1, raw_codes))

      assert {:ok, %RegionSpeciesCodes.Response{region: @region, codes: ["bbwduc" | _]}} =
               RegionSpeciesCodes.get({:region_species_codes, @region}, service)
    end
  end

  def success_response(conn, raw_codes) do
    Plug.Conn.resp(conn, 200, raw_codes)
  end
end
