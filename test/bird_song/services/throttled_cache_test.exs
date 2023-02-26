defmodule ThrottledCacheUnderTest do
  use BirdSong.Services.ThrottledCache, ets_opts: [], ets_name: :throttled_cache_test

  def get_from_api(_id) do
    :bird_song
    |> Application.get_env(:throttled_cache_bypass_url)
    |> Path.join("throttled_cache_test")
    |> HTTPoison.get!()
    |> Map.fetch!(:body)
    |> Jason.decode()
  end
end

defmodule BirdSong.Services.ThrottledCacheTest do
  use ExUnit.Case

  alias BirdSong.{Bird, Services}
  alias Services.Helpers

  @red_shouldered_hawk %Bird{sci_name: "Buteo lineatus", common_name: "Red-shouldered Hawk"}
  @carolina_wren %Bird{sci_name: "Thryothorus ludovicianus", common_name: "Carolina Wren"}
  @eastern_bluebird %Bird{sci_name: "Sialia sialis", common_name: "Eastern Bluebird"}

  setup do
    bypass = Bypass.open()

    Bypass.expect(bypass, "GET", "/throttled_cache_test", &success_response/1)

    Application.put_env(
      :bird_song,
      :throttled_cache_bypass_url,
      "http://localhost:#{bypass.port}"
    )

    {:ok, cache} = start_supervised(ThrottledCacheUnderTest)

    {:ok, bypass: bypass, cache: cache}
  end

  describe "ThrottledCache" do
    test "uses cache", %{bypass: bypass, cache: cache} do
      assert :not_found = ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache)

      assert {:ok, response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)

      assert {:ok, ^response} =
               ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache)

      Bypass.down(bypass)

      assert {:ok, ^response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)
    end

    @tag expect: &__MODULE__.success_response/1
    test "throttles requests", %{cache: cache} do
      throttle_ms = Helpers.get_env(BirdSong.Services.ThrottledCache, :throttle_ms)
      ThrottledCacheUnderTest.clear_cache(cache)

      Enum.map(
        [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird],
        &ThrottledCacheUnderTest.get(&1, cache)
      )

      assert_receive {:end_request, %{bird: @red_shouldered_hawk, time: hawk_end_time}}
      assert_receive {:start_request, %{bird: @carolina_wren, time: wren_start_time}}

      diff = DateTime.diff(wren_start_time, hawk_end_time, :millisecond)
      assert diff >= throttle_ms and diff <= throttle_ms + 10
    end
  end

  @tag expect_once: &__MODULE__.success_response/1
  test "&ThrottledCache.clear_cache/1", %{cache: cache} do
    assert GenServer.cast(cache, :clear_cache) === :ok
    assert {:ok, response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)
    assert {:ok, ^response} = ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache)
    ThrottledCacheUnderTest.clear_cache(cache)
    assert ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache) === :not_found
  end

  def success_response(conn) do
    Plug.Conn.resp(conn, 200, Jason.encode!(%{id: Ecto.UUID.generate()}))
  end
end
