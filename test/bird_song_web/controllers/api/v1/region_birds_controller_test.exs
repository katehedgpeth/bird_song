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
      BirdSong.StaticData.seed_taxonomy("test/mock_data")
      MockEbirdServer.setup(tags)
      conn = get(conn, path)

      response = json_response(conn, :ok)
      assert Map.keys(response) == ["birds"]
      assert is_list(response["birds"])
      assert length(response["birds"]) > 0

      [bird | _] = response["birds"]

      assert Map.keys(bird) == [
               "banding_codes",
               "category",
               "common_name",
               "common_name_codes",
               "family",
               "id",
               "order",
               "sci_name",
               "sci_name_codes",
               "species_code",
               "taxon_order"
             ]
    end
  end
end
