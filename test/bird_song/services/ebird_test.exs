defmodule BirdSong.Services.EbirdTest do
  use BirdSong.MockApiCase
  alias BirdSong.Services.Ebird

  @moduletag service: :ebird

  @forsyth_county "US-NC-067"

  @recent_observations "test/mock_data/recent_observations.json"
                       |> Path.relative_to_cwd()
                       |> File.read!()

  test "url builds a full endpoint", %{bypass: bypass} do
    assert Ebird.url("/product/spplist/" <> @forsyth_county) ===
             mock_url(bypass) <> "/v2/product/spplist/" <> @forsyth_county
  end

  describe "get_recent_observations" do
    @tag expect_once: &__MODULE__.recent_observations_success_response/1
    test "returns a list of recent observations" do
      expected =
        @recent_observations
        |> Jason.decode!()
        |> Enum.map(&Ebird.Observation.parse/1)

      assert {:ok, observations} = Ebird.get_recent_observations(@forsyth_county)
      assert observations === expected
    end

    @tag expect_once: &__MODULE__.not_found_response/1
    test "returns {:error, {:not_found, $URL}} for 404 response", %{bypass: bypass} do
      assert Ebird.get_recent_observations(@forsyth_county) ==
               {:error,
                {:not_found,
                 mock_url(bypass) <> "/v2/data/obs/" <> @forsyth_county <> "/recent?back=30"}}
    end

    @tag expect_once: &__MODULE__.error_response/1
    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code" do
      assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
               Ebird.get_recent_observations(@forsyth_county)
    end

    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
               Ebird.get_recent_observations(@forsyth_county)
    end
  end

  def recent_observations_success_response(conn),
    do: Plug.Conn.resp(conn, 200, @recent_observations)

  def not_found_response(conn), do: Plug.Conn.resp(conn, 404, "unknown region")

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  def update_base_url(value), do: Application.put_env(:bird_song, :ebird, base_url: value)
end
