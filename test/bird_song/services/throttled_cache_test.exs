defmodule ThrottledCacheUnderTest do
  use BirdSong.Services.ThrottledCache, ets_opts: [], ets_name: :throttled_cache_test

  defmodule Response do
    defstruct [:id]

    def parse(%{"id" => id}, _request) do
      %__MODULE__{id: id}
    end
  end

  def endpoint(%Bird{}) do
    "throttled_cache_test"
  end

  def data_file_name(%Bird{}), do: "data_file"
end

defmodule BirdSong.Services.ThrottledCacheTest do
  use ExUnit.Case
  import BirdSong.TestSetup

  alias BirdSong.{
    Bird,
    Services.DataFile,
    Services.Service,
    TestHelpers
  }

  @moduletag :capture_log
  @moduletag :tmp_dir
  @moduletag throttle_ms: 5

  @red_shouldered_hawk %Bird{sci_name: "Buteo lineatus", common_name: "Red-shouldered Hawk"}
  @carolina_wren %Bird{sci_name: "Thryothorus ludovicianus", common_name: "Carolina Wren"}
  @eastern_bluebird %Bird{sci_name: "Sialia sialis", common_name: "Eastern Bluebird"}

  setup [:setup_bypass, :mock_response, :start_throttler, :start_cache]

  describe "ThrottledCache" do
    test "uses cache", %{bypass: bypass, cache: cache} do
      assert :not_found =
               ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache.whereis)

      assert {:ok, response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)

      assert {:ok, ^response} =
               ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, cache.whereis)

      Bypass.down(bypass)

      assert {:ok, ^response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)
    end

    @tag expect: &__MODULE__.success_response/1
    test "throttles requests", %{cache: cache, throttle_ms: throttle_ms} do
      ThrottledCacheUnderTest.register_request_listener(cache.whereis)
      ThrottledCacheUnderTest.clear_cache(cache.whereis)
      state = GenServer.call(cache.whereis, :state)
      throttler = Map.fetch!(state, :throttler)
      assert is_pid(throttler)
      assert %{throttle_ms: ^throttle_ms} = GenServer.call(throttler, :state)

      Enum.map(
        [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird],
        &ThrottledCacheUnderTest.get(&1, cache)
      )

      assert_receive {:end_request, %{bird: @red_shouldered_hawk, response: hawk_response}}
      assert_receive {:end_request, %{bird: @carolina_wren, response: wren_response}}
      assert %{timers: %{responded: hawk_responded}} = hawk_response
      assert %{timers: %{sent: wren_sent}} = wren_response

      diff = NaiveDateTime.diff(wren_sent, hawk_responded, :millisecond)
      assert diff >= throttle_ms
      assert diff <= throttle_ms + 10
    end
  end

  @tag expect_once: &__MODULE__.success_response/1
  test "&ThrottledCache.clear_cache/1", %{cache: cache} do
    assert %Service{whereis: whereis} = cache
    assert GenServer.cast(whereis, :clear_cache) === :ok

    assert {:ok, response} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)

    assert {:ok, ^response} =
             ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, whereis)

    ThrottledCacheUnderTest.clear_cache(whereis)

    assert ThrottledCacheUnderTest.get_from_cache(@red_shouldered_hawk, whereis) === :not_found
  end

  describe "writes a response to disk" do
    @describetag :tmp_dir

    @tag expect_once: &__MODULE__.success_response/1
    test "writes to disk if data file instance is running", %{
      tmp_dir: tmp_dir,
      cache: cache
    } do
      GenServer.cast(cache.whereis, {:update_write_config, true})
      state = GenServer.call(cache.whereis, :state)
      assert is_pid(state.data_file_instance)
      DataFile.register_listener(state.data_file_instance)
      assert Process.alive?(state.data_file_instance) === true
      data_folder = Path.join(tmp_dir, "misc")
      assert File.ls(tmp_dir) === {:ok, ["misc"]}
      assert {:ok, _} = ThrottledCacheUnderTest.get(@red_shouldered_hawk, cache)
      assert_receive {DataFile, {:ok, %{written?: true, path: path}}}
      assert path =~ "/misc/"
      assert File.ls(data_folder) === {:ok, ["data_file.json"]}
    end
  end

  def success_response(conn) do
    Plug.Conn.resp(conn, 200, Jason.encode!(%{id: Ecto.UUID.generate()}))
  end

  defp start_cache(%{} = tags) do
    {:ok, cache: TestHelpers.start_service_supervised(ThrottledCacheUnderTest, tags)}
  end

  defp mock_response(%{use_bypass?: false}) do
    :ok
  end

  defp mock_response(%{bypass: %Bypass{} = bypass}) do
    Bypass.expect(bypass, "GET", "/throttled_cache_test", &success_response/1)
    {:ok, bypass: bypass}
  end
end
