defmodule BirdSong.Services.Ebird.RegionCodesTest do
  use ExUnit.Case

  alias BirdSong.TestHelpers
  alias BirdSong.Services.Ebird.RegionCodes
  @region "US-NC-067"

  setup_all do
    {:ok, raw_codes: File.read!("test/mock_data/region_codes/" <> @region <> ".json")}
  end

  setup %{raw_codes: raw_codes} do
    bypass = Bypass.open()
    {:ok, service} = RegionCodes.start_link(base_url: TestHelpers.mock_url(bypass))
    {:ok, service: service}
  end

  describe "&get/1" do
    test "returns a list of species codes when API returns a successful response", %{
      service: service,
      bypass: bypass
    } do
      Bypass.expect(bypass, &success_response(&1, raw_codes))

      assert {:ok, %RegionCodes.Response{region: @region, codes: ["bbwduc" | _]}} =
               RegionCodes.get({:region_codes, @region}, service)
    end
  end

  def success_response(conn, raw_codes) do
    Plug.Conn.resp(conn, 200, raw_codes)
  end
end
