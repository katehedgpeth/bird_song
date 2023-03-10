defmodule BirdSong.ServicesTest do
  use BirdSong.MockApiCase
  alias BirdSong.{Bird, Services, MockServer}
  alias Services.{Flickr, XenoCanto, Service}

  @moduletag services: [:flickr, :xeno_canto]
  @moduletag :capture_log
  @moduletag expect: &MockServer.success_response/1

  setup %{services: %Services{} = services, bird: %Bird{}} do
    {:ok, responses: Services.fetch_data_for_bird(services)}
  end

  describe "&fetch_data_for_bird/1" do
    @tag bird: @eastern_bluebird
    test "fetches data from all services for the specified bird", %{
      responses: responses,
      bird: %Bird{common_name: common_name}
    } do
      assert %Services{
               bird: %Bird{common_name: ^common_name},
               images: %Service{response: images},
               recordings: %Service{response: recordings}
             } = responses

      assert {:ok, %Flickr.Response{}} = images
      assert {:ok, %XenoCanto.Response{}} = recordings
    end

    @tag bird: @carolina_wren
    test "populates data with {:error, _} when a service gives a bad response", %{
      bird: %Bird{common_name: common_name},
      responses: responses
    } do
      assert %Services{
               bird: %Bird{common_name: ^common_name},
               images: %Service{response: images},
               recordings: %Service{response: recordings}
             } = responses

      assert {:ok, %Flickr.Response{}} = images
      assert {:error, {:not_found, url}} = recordings
      assert url =~ "/api/2/recordings?query=Thryothorus+ludovicianus"
    end
  end
end
