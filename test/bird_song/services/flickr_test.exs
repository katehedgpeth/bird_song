defmodule BirdSong.Services.FlickrTest do
  use BirdSong.MockApiCase

  alias BirdSong.{
    Services,
    Services.DataFile,
    Services.Flickr,
    Services.Service
  }

  @bird @carolina_wren

  @moduletag services: [Flickr]

  setup_all do
    {:ok, images} =
      DataFile.read(%DataFile.Data{request: @bird, service: Map.fetch!(%Services{}, :images)})

    {:ok, images: images}
  end

  describe "&get_image/1" do
    setup [:listen_to_services]

    @tag use_mock: false
    test "returns {:ok, %Flickr.Response{}} when request is successful", %{
      bypass: bypass,
      images: images,
      services: %Services{images: %Service{whereis: whereis}}
    } do
      Bypass.expect(bypass, &Plug.Conn.resp(&1, 200, images))
      assert {:ok, response} = Flickr.get_images(@bird, whereis)

      assert %Flickr.Response{
               images: [%Flickr.Photo{url: "https://live.staticflickr.com" <> path} | _]
             } = response

      assert String.ends_with?(path, ".jpg")
    end

    @tag expect_once: &MockServer.not_found_response/1
    test "returns {:error, {:not_found, url}} when API returns 404", %{
      services: %Services{images: %Service{whereis: whereis}}
    } do
      url = Flickr.url(@red_shouldered_hawk)
      assert GenServer.call(whereis, {:get_from_cache, @bird}) === :not_found

      assert Flickr.get_images(@red_shouldered_hawk, whereis) ===
               {:error, {:not_found, url}}
    end
  end
end
