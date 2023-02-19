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

  test "url builds a full endpoint", %{bypass: bypass} do
    assert Ebird.url("/product/spplist/" <> @forsyth_county) ===
             mock_url(bypass) <> "/v2/product/spplist/" <> @forsyth_county
  end

  describe "get_region_list/1" do
    @tag expect_once: &__MODULE__.success_response/1
    test "calls /product/spplist" do
      assert Ebird.get_region_list(@forsyth_county) == {:ok, @species_list}
    end

    @tag expect_once: &__MODULE__.not_found_response/1
    test "returns {:error, {:not_found, $REGION}} for 404 response" do
      assert Ebird.get_region_list(@forsyth_county) == {:error, {:not_found, @forsyth_county}}
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

  def success_response(conn) do
    Plug.Conn.resp(
      conn,
      200,
      Jason.encode!(@species_list)
    )
  end

  def not_found_response(conn), do: Plug.Conn.resp(conn, 404, "unknown region")

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  def update_base_url(value), do: Application.put_env(:bird_song, :ebird, base_url: value)
end
