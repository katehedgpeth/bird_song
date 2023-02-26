defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.MockApiCase
  alias Plug.Conn
  alias BirdSong.Services
  alias Services.XenoCanto
  alias XenoCanto.{Cache, Response, Recording}

  @moduletag services: [:xeno_canto]

  @tag use_mock: false
  test "&url/1 builds a full URL", %{bypass: bypass} do
    assert XenoCanto.url("test") === mock_url(bypass) <> "/api/2/recordings?query=test"
  end

  describe "&get_recordings/1" do
    @tag stub: {"GET", "/api/2/recordings", &__MODULE__.success_response/1}
    test "returns a response object when request is successful", %{xeno_canto_cache: cache} do
      assert Cache.get_from_cache(@red_shouldered_hawk, cache) === :not_found
      assert {:ok, response} = XenoCanto.get_recordings(@red_shouldered_hawk, cache)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 124
      assert [%Recording{} | _] = recordings

      assert %Recording{
               also: [
                 "Tufted Titmouse",
                 "Northern Parula",
                 "Northern Cardinal"
               ]
             } = Enum.find(recordings, &(length(&1.also) > 0))
    end
  end

  def success_response(%Conn{params: %{"query" => query}} = conn) do
    Conn.resp(conn, 200, Map.fetch!(@recordings, query))
  end

  def error_response(conn) do
    Conn.resp(conn, 404, "not found")
  end
end
