defmodule BirdSong.Services.Ebird.RecordingsTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup
  alias BirdSong.{}

  alias BirdSong.{
    Bird,
    Services.Ebird.Recordings,
    Services.Service,
    TestHelpers
  }

  @moduletag :tmp_dir
  @moduletag :capture_log

  setup_all do
    {:ok,
     mock_data: File.read!("test/mock_data/ebird_recordings.json"),
     mock_html: File.read!("test/mock_data/ebird_recordings.html")}
  end

  setup [:seed_from_mock_taxonomy]
  # setup [:start_services]
  # setup [:listen_to_services]

  setup tags do
    %{mock_data: mock_data, mock_html: mock_html} = tags

    bypass = Bypass.open()

    service =
      TestHelpers.start_service_supervised(
        Recordings,
        Map.merge(tags, %{bypass: bypass, throttle_ms: 0})
      )

    Recordings.register_request_listener(service.whereis)

    Bypass.expect(bypass, "GET", "/catalog", &success_response(&1, mock_html))
    Bypass.expect(bypass, "GET", "/api/v2/search", &success_response(&1, mock_data))
    Bypass.stub(bypass, :any, :any, &Plug.Conn.resp(&1, 404, ""))

    {:ok, bypass: bypass, service: service}
  end

  def success_response(conn, "" <> mock_response) do
    Plug.Conn.resp(conn, 200, mock_response)
  end

  @tag recordings_module: Recordings
  test "get/2", %{
    service: %Service{} = service,
    tmp_dir: tmp_dir
  } do
    bird = BirdSong.Repo.get_by(Bird, common_name: "Eastern Bluebird")
    assert %{data_folder_path: folder} = GenServer.call(service.whereis, :state)
    assert folder =~ tmp_dir
    assert {:ok, %Recordings.Response{recordings: recordings}} = Recordings.get(bird, service)

    # does not shut down port after receiving response
    state = GenServer.call(service.whereis, :state)
    assert %{scraper: {Recordings.Playwright, scraper_pid}} = state
    assert %{port: port} = GenServer.call(scraper_pid, :state)
    assert {:connected, _} = Port.info(port, :connected)

    assert_receive {
      Recordings.Playwright,
      %DateTime{},
      {:request, %{current_request_number: 1, responses: []}}
    }

    assert is_list(recordings)
    assert length(recordings) === 90

    for recording <- recordings do
      assert %Recordings.Recording{asset_id: asset_id, location: location} = recording
      assert is_integer(asset_id)
      assert is_map(location)

      assert Map.keys(location) === [
               "countryCode",
               "countryName",
               "latitude",
               "locId",
               "locality",
               "localityDir",
               "localityKm",
               "longitude",
               "name",
               "subnational1Code",
               "subnational1Name",
               "subnational2Code",
               "subnational2Name"
             ]
    end

    # File.write()
    # assert Map.keys(recording) === []
    # assert_receive :FAIL
  end
end
