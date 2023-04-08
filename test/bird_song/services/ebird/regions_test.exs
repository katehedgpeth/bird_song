defmodule BirdSong.Services.Ebird.RegionsTest do
  use ExUnit.Case, async: true
  import BirdSong.TestSetup

  alias BirdSong.{
    Services.Ebird.Regions,
    Services.Ebird.Regions.Region,
    TestHelpers
  }

  @moduletag :tmp_dir
  @moduletag throttle_ms: 3_000

  setup [:setup_bypass]

  setup %{bypass: bypass} = tags do
    Bypass.expect(bypass, &success_response/1)
    service = TestHelpers.start_service_supervised(Regions, tags)
    {:ok, service: service}
  end

  test "&get_countries/1", %{service: service} do
    assert {:ok,
            %Regions.Response{
              level: :country,
              country: "world",
              regions: regions
            }} = Regions.get_countries(service)

    assert regions === [
             %Region{name: "Afghanistan", code: "AF", level: :country, country: "world"},
             %Region{name: "Albania", code: "AL", level: :country, country: "world"},
             %Region{name: "Algeria", code: "DZ", level: :country, country: "world"},
             %Region{name: "American Samoa", code: "AS", level: :country, country: "world"}
           ]
  end

  def success_response(
        %Plug.Conn{path_info: ["v2", "ref", "region", "list", level, _country]} = conn
      )
      when level in ["country", "subnational1", "subnational2"] do
    Plug.Conn.resp(
      conn,
      200,
      ~s([
      { "code": "AF", "name": "Afghanistan" },
      { "code": "AL", "name": "Albania" },
      { "code": "DZ", "name": "Algeria" },
      { "code": "AS", "name": "American Samoa" }
      ])
    )
  end
end
