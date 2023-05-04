defmodule BirdSong.Data.Recorder.WorkerTest do
  use ExUnit.Case
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Bird,
    Data.Recorder,
    Data.Scraper,
    Services,
    Services.Flickr,
    Services.MacaulayLibrary,
    Services.Service
  }

  @moduletag :broken

  describe "&fetch_data_for_bird/1" do
    @describetag services: [:flickr, :xeno_canto]
    @describetag inject_playwright?: true

    @tag bird: @eastern_bluebird
    @tag :tmp_dir
    @tag seed_services?: false
    @tag playwright_response: {:file, "test/mock_data/ebird_recordings.json"}
    test "fetches data from all services for the specified bird", %{
      services: services,
      bird: bird
    } do
      assert_file_not_exist(bird, services)
      assert %Bird{common_name: common_name} = bird

      assert %Recorder.Worker{
               images_response: images,
               recordings_response: recordings
             } = Recorder.Worker.fetch_data_for_bird(services)

      for module <- [Flickr, MacaulayLibrary.Recordings] do
        for status <- [:start_request, :end_request] do
          assert_receive {^status, %{bird: %Bird{common_name: ^common_name}, module: ^module}},
                         500
        end
      end

      assert {:ok, %Flickr.Response{}} = images
      assert {:ok, %MacaulayLibrary.Response{}} = recordings
    end

    @tag :broken
    @tag bird: @carolina_wren
    @tag :tmp_dir
    @tag use_route_mocks?: false
    @tag playwright_response:
           {:error, Scraper.BadResponseError.exception(status: 404, url: "$FAKED_URL")}
    test "populates data with {:error, _} when a service gives a bad response", %{
      bird: bird,
      services: services
    } do
      assert_file_not_exist(bird, services)
      assert %Bird{common_name: common_name} = bird

      assert %Recorder.Worker{
               bird: %Bird{common_name: ^common_name},
               images_response: images,
               recordings_response: recordings,
               overwrite?: false
             } = Recorder.Worker.fetch_data_for_bird(services)

      assert {:ok, %Flickr.Response{}} = images
      assert {status, data} = recordings
      assert status === :error
      assert {:not_found, url} = data
      assert url =~ "$FAKED_URL"
    end

    @tag bird: @eastern_bluebird
    @tag use_mock_routes?: false
    @tag playwright_response: {:ok, [%{}]}
    test "does not call service if file exists and overwrite? is false", %{
      bird: bird,
      services: services
    } do
      assert_file_exists(bird, services)

      assert %Recorder.Worker{
               images_response: %Flickr{} = images,
               recordings_response: %{response: recordings},
               overwrite?: false
             } = Recorder.Worker.fetch_data_for_bird(services)

      assert %Flickr{PhotoSearch: %{response: images}} = images

      for module <- [Flickr, MacaulayLibrary.Recordings] do
        for status <- [:start_request, :end_request] do
          refute_receive {^status, %{module: ^module}}
        end
      end

      assert {:ok, images_response} = images
      assert is_struct(images_response, Flickr.Response)
      assert {:ok, recordings_response} = recordings
      assert is_struct(recordings_response, MacaulayLibrary.Response)
    end
  end

  def assert_file_not_exist(%Bird{} = bird, %Recorder.Worker{
        images_response: flickr,
        recordings_response: recordings
      }) do
    assert %Flickr{PhotoSearch: %Service{}} = flickr
    assert {:error, {:enoent, _}} = Services.Worker.read_from_disk(flickr, bird)
    assert %{module: MacaulayLibrary.Recordings} = recordings
    assert {:error, {:enoent, _}} = Services.Worker.read_from_disk(recordings, bird)
  end

  def assert_file_exists(%Bird{} = bird, %Recorder.Worker{
        images_response: images,
        recordings_response: recordings
      }) do
    assert %Flickr{PhotoSearch: %{} = images} = images
    assert {:ok, "" <> _} = Services.Worker.read_from_disk(images, bird)

    assert %Service{module: MacaulayLibrary.Recordings} = recordings
    assert {:ok, "" <> _} = Services.Worker.read_from_disk(recordings, bird)
  end
end
