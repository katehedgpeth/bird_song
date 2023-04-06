defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.DataCase
  use BirdSong.MockDataAttributes
  import BirdSong.TestSetup

  alias BirdSong.{
    Bird,
    Services.Ebird,
    Services.Service,
    Services.XenoCanto.Response,
    Services.XenoCanto.Recording,
    TestHelpers
  }

  @moduletag bird: @eastern_bluebird
  @moduletag :tmp_dir
  @moduletag seed_services?: false

  setup [:setup_bypass]

  setup %{
          bypass: bypass
        } = tags do
    Ebird.Taxonomy.seed([
      %{
        "sciName" => "Sialia sialis",
        "comName" => "Eastern Bluebird",
        "speciesCode" => "easblu",
        "category" => "species",
        "taxonOrder" => 27535.0,
        "bandingCodes" => [
          "EABL"
        ],
        "comNameCodes" => [],
        "sciNameCodes" => [
          "SISI"
        ],
        "order" => "Passeriformes",
        "familyCode" => "turdid1",
        "familyComName" => "Thrushes and Allies",
        "familySciName" => "Turdidae"
      }
    ])

    %Service{whereis: whereis} = TestHelpers.start_service_supervised(XenoCanto, tags)
    Bypass.expect(bypass, "GET", "/api/2/recordings", &success_response/1)
    {:ok, whereis: whereis}
  end

  describe "&get/1" do
    test "returns a response object when request is successful", %{
      bird: %Bird{} = bird,
      whereis: whereis
    } do
      assert XenoCanto.get_from_cache(bird, whereis) === :not_found
      assert {:ok, response} = XenoCanto.get(bird, whereis)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 153
      assert [%Recording{} | _] = recordings
    end

    @tag :skip
    test "changes :also to common names when found", %{bird: bird, whereis: whereis} do
      assert {:ok, %Response{recordings: recordings}} = XenoCanto.get(bird, whereis)

      assert %Recording{
               also: [
                 "Tufted Titmouse",
                 "Northern Parula",
                 "Northern Cardinal"
               ]
             } = Enum.filter(recordings, &(length(&1.also) > 2)) |> Enum.at(5)
    end
  end

  def success_response(%Plug.Conn{path_info: ["api", "2", "recordings"]} = conn) do
    Plug.Conn.resp(conn, 200, File.read!("data/recordings/xeno_canto/Eastern_Bluebird.json"))
  end
end
