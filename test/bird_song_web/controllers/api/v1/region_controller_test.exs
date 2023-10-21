defmodule BirdSongWeb.Api.V1.RegionControllerTest do
  use BirdSongWeb.ApiConnCase

  describe "returns 401 when user is not logged in" do
    @describetag login?: false

    test "GET /api/v1/regions", %{conn: conn} do
      conn = get(conn, Routes.api_v1_region_path(conn, :index))
      assert json_response(conn, :unauthorized) == %{"message" => "Login required."}
    end
  end

  describe "GET /api/v1/quiz" do
    test "returns 400 if name parameter is missing", %{conn: conn} do
      conn = get(conn, Routes.api_v1_region_path(conn, :index))

      assert json_response(conn, :bad_request) == %{
               "error" => true,
               "message" => "Missing required parameter: name"
             }
    end

    test "returns 400 if name is less than 3 characters", %{conn: conn} do
      conn_0 = get(conn, Routes.api_v1_region_path(conn, :index, name: ""))

      assert json_response(conn_0, :bad_request) == %{
               "error" => true,
               "message" => "Name must be at least 3 characters."
             }

      conn_1 = get(conn, Routes.api_v1_region_path(conn, :index, name: "F"))
      assert json_response(conn_1, :bad_request)

      conn_2 = get(conn, Routes.api_v1_region_path(conn, :index, name: "Fo"))
      assert json_response(conn_2, :bad_request)
    end

    test "returns a list of matching regions", %{conn: conn} do
      conn = get(conn, Routes.api_v1_region_path(conn, :index, name: "For"))

      response = json_response(conn, :ok)
      assert Map.keys(response) == ["regions"]

      assert length(response["regions"]) == 5

      assert Enum.map(response["regions"], & &1["short_name"]) == [
               "Beaufort",
               "Forsyth",
               "Guilford",
               "Hertford",
               "Rutherford"
             ]
    end
  end
end
