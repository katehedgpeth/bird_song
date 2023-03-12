defmodule BirdSong.Services.EbirdTest do
  use BirdSong.MockApiCase
  alias BirdSong.MockServer
  alias ExUnit.CaptureLog
  alias BirdSong.Services.Ebird

  @moduletag services: [Ebird]

  @forsyth_county "US-NC-067"

  setup_all do
    recent_observations =
      "test/mock_data/recent_observations.json"
      |> Path.relative_to_cwd()
      |> File.read!()

    {:ok, recent_observations: recent_observations}
  end

  setup tags do
    bypass = Map.fetch!(tags, :bypass)
    {:ok, {Ebird, "http://localhost" <> _}} = update_base_url(Ebird, bypass)
    :ok
  end

  @tag use_mock: false
  @tag skip: false
  test "url builds a full endpoint", %{bypass: bypass} do
    assert Ebird.url({:recent_observations, @forsyth_county}) ===
             mock_url(bypass) <> Path.join(["/v2/data/obs/", @forsyth_county, "recent"])
  end

  describe "get_recent_observations" do
    setup [:start_service]

    @tag use_mock: false
    test "returns a list of recent observations", %{
      bypass: bypass,
      recent_observations: recent_observations,
      ebird_instance: instance
    } do
      Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, recent_observations))

      expected =
        recent_observations
        |> Jason.decode!()
        |> Ebird.Response.parse()

      assert Ebird.get_recent_observations(@forsyth_county, instance) === {:ok, expected}
    end

    @tag expect_once: &MockServer.not_found_response/1
    test "returns {:error, {:not_found, $URL}} for 404 response", %{
      bypass: bypass,
      ebird_instance: instance
    } do
      log =
        CaptureLog.capture_log(fn ->
          assert Ebird.get_recent_observations(@forsyth_county, instance) ==
                   {:error,
                    {:not_found,
                     mock_url(bypass) <> "/v2/data/obs/" <> @forsyth_county <> "/recent?back=30"}}
        end)

      assert log =~ "status_code=404 url=" <> mock_url(bypass)
    end

    @tag expect_once: &MockServer.error_response/1
    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code", %{
      ebird_instance: instance
    } do
      log =
        CaptureLog.capture_log(fn ->
          assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
                   Ebird.get_recent_observations(@forsyth_county, instance)
        end)

      assert log =~ "status_code=500"
    end

    @tag use_mock: false
    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{
      bypass: bypass,
      ebird_instance: instance
    } do
      Bypass.down(bypass)

      log =
        CaptureLog.capture_log(fn ->
          assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
                   Ebird.get_recent_observations(@forsyth_county, instance)
        end)

      assert log =~ "status_code=unknown url=unknown error=econnrefused"
    end
  end

  defp start_service(tags) do
    {:ok, instance} = start_service_supervised(Ebird, tags)
    {:ok, ebird_instance: instance}
  end
end
