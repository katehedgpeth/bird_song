defmodule BirdSong.Services.Ebird.RegionSpeciesCodesTest do
  use BirdSong.SupervisedCase

  alias BirdSong.Services.{
    Ebird,
    Ebird.RegionSpeciesCodes
  }

  @moduletag service: :Ebird

  @region "US-NC-067"

  setup_all do
    {:ok, raw_codes: File.read!("test/mock_data/region_species_codes/" <> @region <> ".json")}
  end

  setup tags do
    {:ok, get_worker_setup(Ebird, :RegionSpeciesCodes, tags)}
  end

  describe "&get/1" do
    test "returns a list of species codes when API returns a successful response", %{
      bypass: bypass,
      raw_codes: raw_codes,
      worker: worker
    } do
      Bypass.expect(bypass, &success_response(&1, raw_codes))

      assert {:ok, response} =
               RegionSpeciesCodes.get(
                 {:region_species_codes, @region},
                 worker
               )

      assert %RegionSpeciesCodes.Response{region: @region, codes: codes} = response
      assert ["bbwduc" | _] = codes
    end
  end

  def success_response(conn, raw_codes) do
    Plug.Conn.resp(conn, 200, raw_codes)
  end
end
