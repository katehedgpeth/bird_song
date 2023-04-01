defmodule BirdSong.ServicesTest do
  use BirdSong.MockApiCase
  alias BirdSong.{Bird, Services, MockServer}
  alias Services.{Ebird, Flickr, XenoCanto, Service, DataFile}

  @moduletag services: [:flickr, :xeno_canto]
  @moduletag :capture_log
  @moduletag expect: &MockServer.success_response/1

  setup [:inject_playwright]

  describe "&fetch_data_for_bird/1" do
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

      assert %Services{
               bird: ^bird,
               images: %Service{response: images},
               recordings: %Service{response: recordings},
               overwrite?: false
             } = Services.fetch_data_for_bird(services)

      for module <- [Flickr, Ebird.Recordings] do
        for status <- [:start_request, :end_request] do
          assert_receive {^status, %{bird: %Bird{common_name: ^common_name}, module: ^module}},
                         500
        end
      end

      assert {:ok, %Flickr.Response{}} = images
      assert {:ok, %Ebird.Recordings.Response{}} = recordings
    end

    @tag bird: @carolina_wren
    @tag :tmp_dir
    @tag use_route_mocks?: false
    @tag playwright_response:
           {:error, Ebird.Recordings.BadResponseError.exception(status: 404, url: "$FAKED_URL")}
    test "populates data with {:error, _} when a service gives a bad response", %{
      bird: bird,
      services: services
    } do
      assert_file_not_exist(bird, services)
      assert %Bird{common_name: common_name} = bird

      assert %Services{
               bird: %Bird{common_name: ^common_name},
               images: %Service{response: images},
               recordings: %Service{response: recordings},
               overwrite?: false
             } = Services.fetch_data_for_bird(services)

      assert {:ok, %Flickr.Response{}} = images
      assert {status, data} = recordings
      assert status === :error
      assert {:not_found, url} = data
      assert url =~ "$FAKED_URL"
    end

    @tag bird: @eastern_bluebird
    @tag use_mock_routes?: false
    test "does not call service if file exists and overwrite? is false", %{
      bird: bird,
      services: services
    } do
      assert_file_exists(bird, services)

      assert %Services{
               images: %Service{response: images},
               recordings: %Service{response: recordings},
               overwrite?: false
             } = Services.fetch_data_for_bird(services)

      for module <- [Flickr, XenoCanto] do
        for status <- [:start_request, :end_request] do
          refute_receive {^status, %{module: ^module}}
        end
      end

      assert {:ok, %{__struct__: images_struct}} = images
      assert images_struct === Flickr.Response
      assert {:ok, %{__struct__: recordings_struct}} = recordings
      assert recordings_struct === Ebird.Recordings.Response
    end
  end

  def assert_file_not_exist(%Bird{} = bird, %Services{images: flickr, recordings: xeno_canto}) do
    data = %DataFile.Data{service: flickr, request: bird}
    assert {:error, {:enoent, "" <> _}} = DataFile.read(data)
    assert {:error, {:enoent, "" <> _}} = DataFile.read(%{data | service: xeno_canto})
  end

  def assert_file_exists(%Bird{} = bird, %Services{images: flickr, recordings: xeno_canto}) do
    data = %DataFile.Data{service: flickr, request: bird}
    assert {:ok, "" <> _} = DataFile.read(data)
    assert {:ok, "" <> _} = DataFile.read(%{data | service: xeno_canto})
  end
end
