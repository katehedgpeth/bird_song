defmodule BirdSong.Services.FlickrTest do
  use BirdSong.MockApiCase
  alias Plug.Conn
  alias ExUnit.CaptureLog
  alias BirdSong.{Services.Flickr, TestHelpers}

  @moduletag services: [:flickr]

  @query @red_shouldered_hawk
         |> Flickr.format_query()
         |> URI.decode_query()

  describe "&get_image/1" do
    @tag expect_once: &__MODULE__.success_response/1
    test "returns {:ok, %Flickr.Response{}} when request is successful" do
      {:ok, cache} = TestHelpers.start_cache(Flickr)

      assert {:ok, response} = Flickr.get_images(@red_shouldered_hawk, cache)

      assert %Flickr.Response{
               photos: [%Flickr.Photo{url: "https://live.staticflickr.com" <> path} | _]
             } = response

      assert String.ends_with?(path, ".jpg")
    end

    @tag expect_once: &__MODULE__.not_found_response/1
    test "returns {:error, {:not_found, url}} when API returns 404" do
      url = Flickr.url(@red_shouldered_hawk)

      assert [log] =
               CaptureLog.capture_log(fn ->
                 {:ok, cache} = TestHelpers.start_cache(Flickr)

                 assert Flickr.get_images(@red_shouldered_hawk, cache) ===
                          {:error, {:not_found, url}}
               end)
               |> TestHelpers.parse_logs()

      assert log =~ "request_status=error status_code=404 url=" <> url
    end
  end

  def success_response(%Conn{params: @query} = conn) do
    Conn.resp(conn, 200, @images)
  end

  def not_found_response(conn) do
    Conn.resp(conn, 404, "not found")
  end
end
