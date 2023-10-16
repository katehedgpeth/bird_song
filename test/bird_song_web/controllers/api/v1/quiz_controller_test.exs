defmodule BirdSongWeb.Api.V1.QuizControllerTest do
  use BirdSongWeb.ApiConnCase

  alias BirdSong.{
    Repo,
    Bird
  }

  describe "returns 401 when user is not logged in" do
    @describetag login?: false

    test "POST /api/v1/quiz", %{conn: conn} do
      conn = post(conn, Routes.api_v1_quiz_path(conn, :create))
      assert json_response(conn, :unauthorized) == %{"message" => "Login required."}
    end
  end

  describe "POST /api/v1/quiz" do
    test "returns an error response if params are invalid", %{conn: conn} do
      conn = post(conn, Routes.api_v1_quiz_path(conn, :create))

      assert json_response(conn, :bad_request) == %{
               "errors" => %{
                 "birds" => ["should have at least 1 item(s)"],
                 "region_code" => ["can't be blank"]
               }
             }

      conn = post(conn, Routes.api_v1_quiz_path(conn, :create, region_code: "US-NC-67"))

      assert json_response(conn, :bad_request) == %{
               "errors" => %{
                 "birds" => ["should have at least 1 item(s)"]
               }
             }
    end

    test "returns a quiz when params are valid", %{conn: conn} do
      path =
        Routes.api_v1_quiz_path(conn, :create, birds: get_bird_ids(), region_code: "US-NC-067")

      conn = post(conn, path)
      response = json_response(conn, 200)
      assert Map.keys(response) == ["quiz"]

      assert Map.keys(response["quiz"]) == [
               "birds",
               "correct_answers",
               "id",
               "incorrect_answers",
               "quiz_length",
               "region_code",
               "use_recent_observations?"
             ]

      assert length(response["quiz"]["birds"]) == 5
    end
  end

  defp seed_taxonomy(), do: BirdSong.StaticData.seed_taxonomy("test/mock_data")

  defp get_bird_ids() do
    seed_taxonomy()

    Bird
    |> Repo.all()
    |> Enum.map(& &1.id)
  end
end
