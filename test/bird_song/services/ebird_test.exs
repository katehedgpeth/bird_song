defmodule BirdSong.Services.EbirdTest do
  use BirdSong.MockApiCase
  alias BirdSong.Services.Ebird

  @moduletag service: :ebird

  @forsyth_county "US-NC-067"

  @species_list [
    "shbdow",
    "lobdow",
    "amewoo",
    "wilsni",
    "wilpha",
    "renpha",
    "sposan",
    "solsan",
    "greyel",
    "willet1"
  ]

  @recent_observations Jason.decode!(~s<[{
    "speciesCode": "gresca",
    "comName": "Greater Scaup",
    "sciName": "Aythya marila",
    "locId": "L4177866",
    "locName": "Salem Lake--Marina",
    "obsDt": "2023-02-07 09:30",
    "howMany": 2,
    "lat": 36.0943088,
    "lng": -80.192771,
    "obsValid": true,
    "obsReviewed": false,
    "locationPrivate": false,
    "subId": "S127807403"
  },
  {
    "speciesCode": "redhea",
    "comName": "Redhead",
    "sciName": "Aythya americana",
    "locId": "L6194728",
    "locName": "Quarry Park",
    "obsDt": "2023-02-06 12:11",
    "howMany": 4,
    "lat": 36.080517,
    "lng": -80.201544,
    "obsValid": true,
    "obsReviewed": false,
    "locationPrivate": false,
    "subId": "S127758449"
  },
  {
    "speciesCode": "amepip",
    "comName": "American Pipit",
    "sciName": "Anthus rubescens",
    "locId": "L22488444",
    "locName": "Shallowford Road, Lewisville, North Carolina, US (36.094, -80.509)",
    "obsDt": "2023-02-06 09:54",
    "howMany": 5,
    "lat": 36.0939015,
    "lng": -80.5085296,
    "obsValid": true,
    "obsReviewed": false,
    "locationPrivate": true,
    "subId": "S127746783"
  }]>)

  test "url builds a full endpoint", %{bypass: bypass} do
    assert Ebird.url("/product/spplist/" <> @forsyth_county) ===
             mock_url(bypass) <> "/v2/product/spplist/" <> @forsyth_county
  end

  describe "get_region_list/1" do
    @tag expect_once: &__MODULE__.region_list_success_response/1
    test "calls /product/spplist" do
      assert Ebird.get_region_list(@forsyth_county) == {:ok, @species_list}
    end

    @tag expect_once: &__MODULE__.not_found_response/1
    test "returns {:error, {:not_found, $URL}} for 404 response", %{bypass: bypass} do
      assert Ebird.get_region_list(@forsyth_county) ==
               {:error,
                {:not_found, mock_url(bypass) <> "/v2/product/spplist/" <> @forsyth_county}}
    end

    @tag expect_once: &__MODULE__.error_response/1
    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code" do
      assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
               Ebird.get_region_list(@forsyth_county)
    end

    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
               Ebird.get_region_list(@forsyth_county)
    end
  end

  describe "get_recent_observations" do
    @tag expect_once: &__MODULE__.recent_observations_success_response/1
    test "returns a list of recent observations" do
      expected = Enum.map(@recent_observations, &Ebird.Observation.parse/1)

      assert {:ok, observations} = Ebird.get_recent_observations(@forsyth_county)
      assert observations === expected
    end
  end

  def region_list_success_response(conn),
    do: Plug.Conn.resp(conn, 200, Jason.encode!(@species_list))

  def recent_observations_success_response(conn),
    do: Plug.Conn.resp(conn, 200, Jason.encode!(@recent_observations))

  def not_found_response(conn), do: Plug.Conn.resp(conn, 404, "unknown region")

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  def update_base_url(value), do: Application.put_env(:bird_song, :ebird, base_url: value)
end
