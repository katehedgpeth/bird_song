defmodule BirdSongWeb.Api.V1.UserControllerTest do
  use BirdSongWeb.ApiConnCase

  alias BirdSong.{
    Bird,
    Quiz
  }

  setup %{user: user} do
    BirdSong.StaticData.seed_taxonomy("test/mock_data")

    {:ok, _} = create_quiz(user)
  end

  describe "returns 401 if user is not logged in" do
    @describetag login?: false

    test "GET /api/v1/users/:user_id/quizzes/current", %{conn: conn, user: user} do
      conn = get(conn, Routes.api_v1_user_quiz_path(conn, :show, user.id, "current"))

      assert json_response(conn, :unauthorized) == %{
               "message" => "Login required."
             }
    end

    test "GET /api/v1/users/:user_id/quizzes/:quiz_id", %{conn: conn, user: user, quiz: quiz} do
      conn = get(conn, Routes.api_v1_user_quiz_path(conn, :show, user.id, quiz.id))

      assert json_response(conn, :unauthorized) == %{
               "message" => "Login required."
             }
    end
  end

  describe "GET /api/v1/users/:user_id/quizzes/:quiz_id" do
    test "returns a quiz if it exists", %{conn: conn, user: user, quiz: old_quiz} do
      assert {:ok, %{quiz: _new_quiz}} = create_quiz(user)

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, old_quiz.id))
        |> json_response(:ok)

      assert Map.keys(response) == ["quiz"]
    end

    test "returns 404 if quiz does not exist", %{conn: conn, user: user} do
      assert BirdSong.Repo.get(Quiz, 1) == nil

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, 1))
        |> json_response(:not_found)

      assert response == %{"message" => "Quiz not found."}
    end

    test "returns 403 if quiz does not belong to user", %{conn: conn, user: user} do
      assert {:ok, %{quiz: new_quiz}} = create_quiz(user_fixture())

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, new_quiz.id))
        |> json_response(:forbidden)

      assert response == %{"message" => "Access forbidden."}
    end
  end

  defp create_quiz(user) do
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
end
