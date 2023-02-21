defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.MockApiCase
  alias BirdSong.Services.XenoCanto
  alias XenoCanto.{Cache, Response, Recording}

  @moduletag service: :xeno_canto

  @red_shouldered_hawk "Buteo lineatus"
  @recordings "test/mock_data/#{String.replace(@red_shouldered_hawk, " ", "_")}.json"
              |> Path.relative_to_cwd()
              |> File.read!()

  setup do
    Cache.clear_cache()
  end

  test "&url/1 builds a full URL", %{bypass: bypass} do
    assert XenoCanto.url("test") === mock_url(bypass) <> "/api/2/recordings?query=test"
  end

  describe "&get_recording/1" do
    @tag expect_once: &__MODULE__.success_response/1
    test "returns a recording path when request is successful" do
      assert {:ok, response} = XenoCanto.get_recording(@red_shouldered_hawk)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 124
      assert [%Recording{} | _] = recordings
    end

    @tag expect_once: &__MODULE__.success_response/1
    test "uses cache", %{bypass: bypass} do
      assert {:ok, response} = XenoCanto.get_recording(@red_shouldered_hawk)
      Bypass.down(bypass)
      assert {:ok, ^response} = XenoCanto.get_recording(@red_shouldered_hawk)
    end
  end

  def success_response(conn) do
    Plug.Conn.resp(conn, 200, @recordings)
  end

  def error_response(conn) do
    Plug.Conn.resp(conn, 404, "not found")
  end
end
