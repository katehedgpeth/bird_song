defmodule BirdSong.Services.EbirdTest do
  use ExUnit.Case
  alias BirdSong.Services.Ebird

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

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    update_base_url(base_url)
    {:ok, bypass: bypass, base_url: base_url}
  end

  test "url builds a full endpoint", %{base_url: base_url} do
    assert Ebird.url("/product/spplist/" <> @forsyth_county) ===
             base_url <> "/v2/product/spplist/" <> @forsyth_county
  end

  describe "get_region_list/1" do
    test "calls /product/spplist", %{bypass: bypass} do
      Bypass.expect_once(bypass, &success_response/1)

      assert Ebird.get_region_list(@forsyth_county) == {:ok, @species_list}
    end

    test "returns {:error, {:not_found, $REGION}} for 404 response", %{bypass: bypass} do
      Bypass.expect_once(bypass, &not_found_response/1)
      assert Ebird.get_region_list(@forsyth_county) == {:error, {:not_found, @forsyth_county}}
    end

    test "returns {:error, {:bad_response, %HTTPoison.Response{}}} for bad status code", %{
      bypass: bypass
    } do
      Bypass.expect_once(bypass, &error_response/1)

      assert {:error, {:bad_response, %HTTPoison.Response{status_code: 500}}} =
               Ebird.get_region_list(@forsyth_county)
    end

    test "returns {:error, %HTTPoison.Error{}} for all other errors", %{bypass: bypass} do
      Bypass.down(bypass)

      assert {:error, %HTTPoison.Error{reason: :econnrefused}} =
               Ebird.get_region_list(@forsyth_county)
    end
  end

  defp success_response(conn) do
    Plug.Conn.resp(
      conn,
      200,
      Jason.encode!(@species_list)
    )
  end

  defp not_found_response(conn), do: Plug.Conn.resp(conn, 404, "unknown region")

  defp error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  defp update_base_url(value), do: Application.put_env(:bird_song, :ebird, base_url: value)
end
