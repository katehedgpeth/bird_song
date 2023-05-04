defmodule BirdSong.Services.XenoCanto do
  use BirdSong.Services.Supervisor,
    base_url: "https://xeno-canto.org",
    caches: [:Recordings],
    use_data_folder?: true
end

defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.DataCase
  use BirdSong.MockDataAttributes

  use BirdSong.SupervisedCase,
    services: [
      BirdSong.Services.XenoCanto,
      BirdSong.Services.Flickr,
      BirdSong.Services.Ebird
    ]

  alias BirdSong.{
    Bird,
    Services.Service,
    Services.Ebird,
    Services.Worker,
    Services.XenoCanto.Response,
    Services.XenoCanto.Recording
  }

  @moduletag bird: @eastern_bluebird
  @moduletag :tmp_dir

  setup tags do
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

    # pid =
    #   start_link_supervised!(
    #     {XenoCanto, [service_name: instance_name, base_url: TestHelpers.mock_url(bypass)]}
    #   )

    assert %{worker: worker, bypass: bypass} = get_worker_setup(XenoCanto, :Recordings, tags)

    Bypass.expect(bypass, "GET", "/api/2/recordings", &success_response/1)
    {:ok, worker: worker}
  end

  @moduletag opts: [service_modules: [Ebird, XenoCanto, Flickr]]

  describe "&Recordings.get/1" do
    test "returns a response object when request is successful", %{
      bird: %Bird{} = bird,
      worker: worker,
      test: test
    } do
      assert %Worker{} = worker
      assert worker.instance_name === Module.concat([test, :XenoCanto, :Recordings])
      assert worker.module === XenoCanto.Recordings
      assert %Service{} = worker.parent
      assert worker.parent.name === Module.concat(test, :XenoCanto)
      assert worker.parent.module === XenoCanto

      assert XenoCanto.Recordings.get_from_cache(bird, worker) === :not_found
      assert {:ok, response} = XenoCanto.Recordings.get(bird, worker)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 153
      assert [%Recording{} | _] = recordings
    end

    @tag :skip
    test "changes :also to common names when found", %{bird: bird, worker: worker} do
      assert {:ok, %Response{recordings: recordings}} = XenoCanto.Recordings.get(bird, worker)

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
