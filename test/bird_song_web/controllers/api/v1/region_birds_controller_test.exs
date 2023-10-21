defmodule BirdSongWeb.Api.V1.RegionBirdsControllerTest do
  alias BirdSong.MockEbirdServer
  use BirdSongWeb.ApiConnCase
  use BirdSong.SupervisedCase

  setup tags do
    region = Map.get(tags, :region, "US-NC-067")

    {:ok,
     path:
       Routes.api_v1_region_birds_path(
         tags.conn,
         :index,
         region,
         services: tags.test
       ),
     region: region}
  end

  describe "returns 401 when user is not logged in" do
    @describetag login?: false

    test "GET /api/v1/regions/:region_id/birds", %{conn: conn, path: path} do
      conn = get(conn, path)
      assert json_response(conn, :unauthorized) == %{"message" => "Login required."}
    end
  end

  describe "GET /api/v1/regions/:region_id/birds" do
    @tag region: "does-not-exist"
    test "returns 404 when region doesn't exist", %{conn: conn, path: path} do
      conn = get(conn, path)

      assert json_response(conn, :not_found) == %{
               "message" => "Unknown region."
             }
    end

    test "returns 503 when service is unavailable", %{conn: conn, path: path} = tags do
      tags
      |> MockEbirdServer.get_bypass()
      |> Bypass.expect(fn conn ->
        Plug.Conn.resp(conn, 503, "")
      end)

      conn = get(conn, path)
      assert json_response(conn, :service_unavailable) == %{"message" => "Service Unavailable."}
    end

    test "returns list of birds when region exists", %{conn: conn, path: path} = tags do
      MockEbirdServer.setup(tags)
      conn = get(conn, path)

      response = json_response(conn, :ok)
      assert Map.keys(response) == ["region", "species_codes"]
      assert is_list(response["species_codes"])
      assert length(response["species_codes"]) > 0

      assert Map.keys(response["region"]) == [
               "code",
               "full_name",
               "max_lat",
               "max_lon",
               "min_lat",
               "min_lon",
               "short_name"
             ]

      assert response["region"]["short_name"] == "Forsyth"

      for code <- Map.fetch!(response, "species_codes") do
        assert is_binary(code)
      end
    end
  end
end
