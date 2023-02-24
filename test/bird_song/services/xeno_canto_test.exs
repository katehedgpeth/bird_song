defmodule BirdSong.Services.XenoCantoTest do
  use BirdSong.MockApiCase
  alias Plug.Conn
  alias BirdSong.Services
  alias Services.{XenoCanto, Helpers}
  alias XenoCanto.{Cache, Response, Recording}

  @moduletag services: [:xeno_canto]

  @tag use_mock: false
  test "&url/1 builds a full URL", %{bypass: bypass} do
    assert XenoCanto.url("test") === mock_url(bypass) <> "/api/2/recordings?query=test"
  end

  @tag use_bypass: false
  test "&clear_cache/0" do
    assert {:ok, _} = XenoCanto.get_recording(@red_shouldered_hawk)
    assert {:ok, %Response{}} = Cache.get_from_cache(@red_shouldered_hawk)
    Cache.clear_cache()
    assert Cache.get_from_cache(@red_shouldered_hawk) === :not_found
  end

  describe "&get_recording/1" do
    @tag stub: {"GET", "/api/2/recordings", &__MODULE__.success_response/1}
    test "returns a recording path when request is successful" do
      assert {:ok, response} = XenoCanto.get_recording(@red_shouldered_hawk)
      assert %Response{recordings: recordings} = response
      assert length(recordings) == 124
      assert [%Recording{} | _] = recordings
    end

    @tag :skip
    @tag expect_once: &__MODULE__.success_response/1
    test "uses cache", %{bypass: bypass} do
      Cache.clear_cache()
      assert [] = Cache.get_from_cache(@red_shouldered_hawk)

      assert {:ok, response} = XenoCanto.get_recording(@red_shouldered_hawk)
      assert [{@red_shouldered_hawk, %Response{}}] = Cache.get_from_cache(@red_shouldered_hawk)

      Bypass.down(bypass)
      assert {:ok, ^response} = XenoCanto.get_recording(@red_shouldered_hawk)
    end

    @tag expect: &__MODULE__.success_response/1
    test "throttles requests" do
      Cache.clear_cache()
      Logger.configure(level: :debug)

      logs =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          Enum.map(
            [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird],
            &XenoCanto.get_recording/1
          )
        end)

      assert [_send_1, receive_1, send_2, receive_2, send_3, _receive_3] =
               logs
               |> String.split("\n")
               |> Enum.flat_map(&String.split(&1, "\e"))
               |> Enum.reject(&(&1 === "" or &1 === "[0m"))
               |> Enum.map(&String.replace(&1, "[36m", ""))
               |> Enum.map(
                 &(&1
                   |> String.split(" [debug] ")
                   |> List.first()
                   |> Time.from_iso8601!())
               )

      throttle_ms = Helpers.get_env(:xeno_canto, :throttle_ms)

      diff1 = Time.diff(send_2, receive_1, :millisecond)
      assert diff1 >= throttle_ms
      assert diff1 <= throttle_ms + 200

      diff2 = Time.diff(send_3, receive_2, :millisecond)
      assert diff2 >= throttle_ms
      assert diff2 <= throttle_ms + 100

      Logger.configure(level: :warn)
    end
  end

  def success_response(%Conn{params: %{"query" => query}} = conn) do
    Conn.resp(conn, 200, Map.fetch!(@recordings, query))
  end

  def error_response(conn) do
    Conn.resp(conn, 404, "not found")
  end
end
