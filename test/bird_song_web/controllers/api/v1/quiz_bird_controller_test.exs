defmodule BirdSongWeb.Api.V1.QuizBirdControllerTest do
  use BirdSongWeb.ApiConnCase
  use BirdSong.SupervisedCase

  alias BirdSong.{
    Bird,
    Quiz
  }

  describe "POST /quizzes/:quiz_id/bird" do
    setup do
      BirdSong.StaticData.seed_taxonomy("test/mock_data")
      :ok
    end

    setup [:create_quiz, :assign_path]

    @tag login?: false
    test "returns 401 if user is not logged in", %{conn: conn, path: path} do
      conn = get(conn, path)

      assert json_response(conn, :unauthorized) == %{
               "message" => "Login required."
             }
    end

    test "returns a random bird with an image and a recording", %{conn: conn, path: path} do
      conn = get(conn, path)
      response = json_response(conn, :ok)
      assert Map.keys(response) == ["bird", "image", "quiz", "recording"]
    end
  end

  defp create_quiz(%{user: user}) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:user, user)
    |> Ecto.Multi.put(:region_code, "US-NC-067")
    |> Ecto.Multi.all(:birds, Bird)
    |> Ecto.Multi.insert(
      :quiz,
      &Quiz.changeset(&1.user, Map.take(&1, [:region_code, :birds]))
    )
    |> BirdSong.Repo.transaction()
  end

  defp assign_path(%{conn: conn, quiz: %Quiz{id: quiz_id}}) do
    {:ok, path: Routes.api_v1_quiz_bird_path(conn, :show, quiz_id, "random")}
  end
end
