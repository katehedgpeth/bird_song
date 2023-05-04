defmodule BirdSong.Services.Ebird.ObservationsTest do
  use BirdSong.SupervisedCase, async: true
  alias BirdSong.MockServer

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Observations
  }

  @moduletag service: :Ebird
  @moduletag :capture_log

  @forsyth_county "US-NC-067"

  setup_all do
    recent_observations =
      "test/mock_data/recent_observations.json"
      |> Path.relative_to_cwd()
      |> File.read!()

    {:ok, recent_observations: recent_observations}
  end

  @tag start_services?: false
  @tag use_bypass?: false
  test "&endpoint/1 returns the correct endpoint", %{} do
    assert Observations.endpoint({:recent_observations, @forsyth_county}) ===
             Path.join(["v2/data/obs/", @forsyth_county, "recent"])
  end

  describe "get_recent_observations" do
    setup tags do
      {:ok, get_worker_setup(Ebird, :Observations, tags)}
    end

    test "returns a list of recent observations", %{
      bypass: bypass,
      worker: worker,
      recent_observations: recent_observations
    } do
      Bypass.expect_once(bypass, &MockServer.success_response/1)

      expected =
        recent_observations
        |> Jason.decode!()
        |> Observations.Response.parse({:recent_observations, @forsyth_county})

      assert Observations.get_recent_observations(
               @forsyth_county,
               worker
             ) ===
               {:ok, expected}
    end

    test "returns {:error, {:not_found, $URL}} for 404 response", %{
      bypass: bypass,
      mock_url: mock_url,
      worker: worker
    } do
      Bypass.expect_once(bypass, &MockServer.not_found_response/1)

      assert Observations.get_recent_observations(@forsyth_county, worker) ==
               {:error,
                {:not_found, Path.join([mock_url, "/v2/data/obs/", @forsyth_county, "/recent"])}}
    end

    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code", %{
      bypass: bypass,
      worker: worker
    } do
      Bypass.expect_once(bypass, &MockServer.error_response/1)

      assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
               Observations.get_recent_observations(@forsyth_county, worker)
    end

    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{
      bypass: bypass,
      worker: worker
    } do
      Bypass.down(bypass)

      assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
               Observations.get_recent_observations(@forsyth_county, worker)
    end
  end
end
