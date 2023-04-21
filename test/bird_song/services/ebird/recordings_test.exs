defmodule BirdSong.Services.Ebird.RecordingsTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup, except: [start_throttler: 1]

  alias BirdSong.Services.RequestThrottlers.MacaulayLibrary
  alias BirdSong.Services.Ebird.Recordings.Playwright

  alias BirdSong.{
    Bird,
    MockMacaulayServer,
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

  setup [:seed_from_taxonomy, :setup_bypass, :start_throttler]

  setup tags do
    if Map.get(tags, :copy_files?, false) do
      tmp_dir = Map.fetch!(tags, :tmp_dir)
      File.cp_r!("data/recordings/ebird", Path.join([tmp_dir, "recordings"]))
    end

    service =
      TestHelpers.start_service_supervised(
        Recordings,
        Map.merge(tags, %{throttle_ms: 0})
      )

    Recordings.register_request_listener(service.whereis)

    {:ok, service: service}
  end

  def success_response(conn, "" <> mock_response) do
    Plug.Conn.resp(conn, 200, mock_response)
  end

  @tag recordings_module: Recordings
  @tag taxonomy_file: TestHelpers.mock_file_path("mock_taxonomy")
  test "get/2",
       %{
         service: %Service{} = service,
         tmp_dir: tmp_dir
       } = tags do
    MockMacaulayServer.setup(tags)
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
  end

  def start_throttler(%{bypass: bypass}) do
    base_url = TestHelpers.mock_url(bypass)

    {:ok, playwright} =
      Playwright.start_link(
        base_url: base_url,
        listeners: [self()],
        throttle_ms: 0
      )

    {:ok, throttler} =
      MacaulayLibrary.start_link(
        base_url: base_url,
        throttle_ms: 0,
        scraper: {Playwright, playwright}
      )

    {:ok, throttler: throttler, scraper: {Playwright, playwright}}
  end
end
