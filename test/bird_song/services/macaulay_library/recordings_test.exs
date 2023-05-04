defmodule BirdSong.Services.MacaulayLibrary.RecordingsTest do
  use BirdSong.SupervisedCase, async: true
  use BirdSong.DataCase, async: true
  import BirdSong.TestSetup, only: [seed_from_taxonomy: 1]

  alias BirdSong.{
    Bird,
    MockMacaulayServer,
    Services.MacaulayLibrary,
    Services.Worker,
    TestHelpers
  }

  @moduletag :tmp_dir
  # @moduletag :capture_log

  setup_all do
    {:ok,
     mock_data: File.read!("test/mock_data/ebird_recordings.json"),
     mock_html: File.read!("test/mock_data/ebird_recordings.html")}
  end

  setup [:seed_from_taxonomy]

  setup tags do
    if Map.get(tags, :copy_files?, false) do
      tmp_dir = Map.fetch!(tags, :tmp_dir)

      File.cp_r!(
        "data/recordings/macaulay_library",
        Path.join([tmp_dir, "recordings", "macaulay_library"])
      )
    end

    :ok
  end

  def success_response(conn, "" <> mock_response) do
    Plug.Conn.resp(conn, 200, mock_response)
  end

  @tag :slow_test
  @tag taxonomy_file: TestHelpers.mock_file_path("mock_taxonomy")
  @tag listen_to: [{MacaulayLibrary, :Playwright}]
  test "get/2", %{} = tags do
    assert {:ok, tmp_dir} = Map.fetch(tags, :tmp_dir)

    playwright = get_worker(MacaulayLibrary, :Playwright, tags)
    assert %Worker{} = playwright
    assert %{listeners: listeners} = GenServer.call(playwright.instance_name, :state)
    assert listeners === [self()]

    MockMacaulayServer.setup(tags)
    bird = BirdSong.Repo.get_by(Bird, common_name: "Eastern Bluebird")

    updated_state = GenServer.call(playwright.instance_name, :state)
    assert %{port: port, ready?: false, base_url: %URI{host: "localhost"}} = updated_state
    assert is_port(port)
    assert {:connected, _} = Port.info(port, :connected)

    worker = get_worker(MacaulayLibrary, :Recordings, tags)

    assert Worker.full_data_folder_path(worker) ===
             {:ok, Path.join(tmp_dir, "recordings/macaulay_library")}

    assert {:ok, %MacaulayLibrary.Response{recordings: recordings}} =
             MacaulayLibrary.Recordings.get(bird, worker)

    # does not shut down port after receiving response
    assert %{port: ^port} = GenServer.call(playwright.instance_name, :state)
    assert {:connected, _} = Port.info(port, :connected)

    assert_receive {
      MacaulayLibrary.Playwright,
      %DateTime{},
      {:request, %{current_request_number: 1, responses: []}}
    }

    assert is_list(recordings)
    assert length(recordings) === 90

    for recording <- recordings do
      assert %MacaulayLibrary.Recording{asset_id: asset_id, location: location} = recording
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
end
