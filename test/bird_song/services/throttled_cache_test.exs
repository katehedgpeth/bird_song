defmodule ThrottledCacheUnderTest do
  use BirdSong.Services.ThrottledCache, ets_opts: [], ets_name: :throttled_cache_test

  defmodule Response do
    defstruct [:id]

    def parse(%{"id" => id}) do
      %__MODULE__{id: id}
    end
  end

  def url({%Bird{}, "" <> mock_url}) do
    Path.join(mock_url, "throttled_cache_test")
  end

  def ets_key({%Bird{sci_name: sci_name}, _mock_url}), do: sci_name

  def message_details({%Bird{} = bird, _url}) do
    %{bird: bird}
  end

  def headers({%Bird{}, _mock_url}), do: []
  def params({%Bird{}, _mock_url}), do: []

  def data_file_name({%Bird{}, _mock_url}), do: "data_file"
end

defmodule BirdSong.Services.ThrottledCacheTest do
  use ExUnit.Case

  alias BirdSong.{
    Bird,
    Services.DataFile,
    Services.Helpers,
    Services.Service,
    TestHelpers
  }

  @moduletag :capture_log

  @red_shouldered_hawk %Bird{sci_name: "Buteo lineatus", common_name: "Red-shouldered Hawk"}
  @carolina_wren %Bird{sci_name: "Thryothorus ludovicianus", common_name: "Carolina Wren"}
  @eastern_bluebird %Bird{sci_name: "Sialia sialis", common_name: "Eastern Bluebird"}

  setup [:start_cache, :mock_response]

  describe "ThrottledCache" do
    test "uses cache", %{bypass: bypass, cache: cache} do
      args = args(bypass)
      assert :not_found = ThrottledCacheUnderTest.get_from_cache(args, cache)

      assert {:ok, response} = ThrottledCacheUnderTest.get(args, cache)

      assert {:ok, ^response} = ThrottledCacheUnderTest.get_from_cache(args, cache)

      Bypass.down(bypass)

      assert {:ok, ^response} = ThrottledCacheUnderTest.get(args, cache)
    end

    @tag expect: &__MODULE__.success_response/1
    test "throttles requests", %{bypass: bypass, cache: cache} do
      ThrottledCacheUnderTest.register_request_listener(cache)
      throttle_ms = Helpers.get_env(BirdSong.Services.ThrottledCache, :throttle_ms)
      ThrottledCacheUnderTest.clear_cache(cache)

      Enum.map(
        [@red_shouldered_hawk, @carolina_wren, @eastern_bluebird],
        &(bypass |> args(&1) |> ThrottledCacheUnderTest.get(cache))
      )

      assert_receive {:end_request, %{bird: @red_shouldered_hawk, time: hawk_end_time}}
      assert_receive {:start_request, %{bird: @carolina_wren, time: wren_start_time}}

      diff = DateTime.diff(wren_start_time, hawk_end_time, :millisecond)
      assert diff >= throttle_ms and diff <= throttle_ms + 10
    end
  end

  @tag expect_once: &__MODULE__.success_response/1
  test "&ThrottledCache.clear_cache/1", %{bypass: bypass, cache: cache} do
    args = args(bypass)
    assert GenServer.cast(cache, :clear_cache) === :ok

    assert {:ok, response} = ThrottledCacheUnderTest.get(args, cache)

    assert {:ok, ^response} = ThrottledCacheUnderTest.get_from_cache(args, cache)

    ThrottledCacheUnderTest.clear_cache(cache)

    assert ThrottledCacheUnderTest.get_from_cache(args, cache) === :not_found
  end

  describe "&ThrottledCache.write_to_disk/3 writes a response to disk" do
    @describetag :tmp_dir
    @describetag use_bypass?: false

    test "does nothing if data file instance is not running", %{
      tmp_dir: tmp_dir,
      cache: cache
    } do
      assert ThrottledCacheUnderTest.write_to_disk(
               {:ok, %HTTPoison.Response{status_code: 200, body: ~s({foo: "bar"})}},
               {@carolina_wren, ""},
               %BirdSong.Services.ThrottledCache.State{
                 data_folder_path: tmp_dir,
                 service: %Service{
                   module: ThrottledCacheUnderTest,
                   whereis: cache
                 }
               }
             ) === {:error, :not_alive}
    end

    test "writes to disk if data file instance is running", %{
      test: test,
      tmp_dir: tmp_dir,
      cache: cache
    } do
      assert {:ok, data_file_instance} =
               start_supervised({DataFile, name: Module.concat(test, DataFile)})

      DataFile.register_listener(data_file_instance)

      request = {@carolina_wren, ""}

      assert ThrottledCacheUnderTest.write_to_disk(
               {:ok, %HTTPoison.Response{status_code: 200, body: ~s({foo: "bar"})}},
               request,
               %BirdSong.Services.ThrottledCache.State{
                 data_folder_path: tmp_dir,
                 data_file_instance: data_file_instance,
                 service: %Service{module: ThrottledCacheUnderTest, whereis: cache}
               }
             ) === :ok

      assert_receive {DataFile, {:ok, %{written?: true, path: path}}}

      assert File.exists?(path)
    end
  end

  def success_response(conn) do
    Plug.Conn.resp(conn, 200, Jason.encode!(%{id: Ecto.UUID.generate()}))
  end

  def args(%Bypass{} = bypass, %Bird{} = bird \\ @red_shouldered_hawk) do
    {bird, TestHelpers.mock_url(bypass)}
  end

  defp start_cache(%{}) do
    {:ok, cache: start_supervised!(ThrottledCacheUnderTest)}
  end

  defp mock_response(%{use_bypass?: false}) do
    :ok
  end

  defp mock_response(%{}) do
    bypass = Bypass.open()
    Bypass.expect(bypass, "GET", "/throttled_cache_test", &success_response/1)
    {:ok, bypass: bypass}
  end
end
