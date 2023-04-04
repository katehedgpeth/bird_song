defmodule BirdSong.Services.Ebird.ObservationsTest do
  use BirdSong.MockApiCase
  alias BirdSong.MockServer

  alias BirdSong.{
    Services,
    Services.Ebird.Observations,
    Services.Service,
    TestHelpers
  }

  @moduletag services: [Observations]
  @moduletag :capture_log

  @forsyth_county "US-NC-067"

  setup_all do
    recent_observations =
      "test/mock_data/recent_observations.json"
      |> Path.relative_to_cwd()
      |> File.read!()

    {:ok, recent_observations: recent_observations}
  end

  setup %{services: %Services{observations: %Service{whereis: instance}}} do
    {:ok, instance: instance}
  end

  @tag use_mock_routes?: false
  test "&endpoint/1 returns the correct endpoint", %{} do
    assert Observations.endpoint({:recent_observations, @forsyth_county}) ===
             Path.join(["v2/data/obs/", @forsyth_county, "recent"])
  end

  describe "get_recent_observations" do
    @tag expect_once: &MockServer.success_response/1
    test "returns a list of recent observations", %{
      recent_observations: recent_observations,
      instance: instance
    } do
      expected =
        recent_observations
        |> Jason.decode!()
        |> Observations.Response.parse()

      assert Observations.get_recent_observations(@forsyth_county, instance) ===
               {:ok, expected}
    end

    @tag expect_once: &MockServer.not_found_response/1
    test "returns {:error, {:not_found, $URL}} for 404 response", %{
      bypass: bypass,
      instance: instance
    } do
      assert Observations.get_recent_observations(@forsyth_county, instance) ==
               {:error,
                {:not_found,
                 TestHelpers.mock_url(bypass) <> "/v2/data/obs/" <> @forsyth_county <> "/recent"}}
    end

    @tag expect_once: &MockServer.error_response/1
    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code", %{
      instance: instance
    } do
      assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
               Observations.get_recent_observations(@forsyth_county, instance)
    end

    @tag use_mock_routes?: false
    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{
      bypass: bypass,
      instance: instance
    } do
      Bypass.down(bypass)

      assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
               Observations.get_recent_observations(@forsyth_county, instance)
    end
  end
end
