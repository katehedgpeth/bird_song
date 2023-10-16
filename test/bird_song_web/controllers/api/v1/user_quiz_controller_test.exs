defmodule BirdSongWeb.Api.V1.UserControllerTest do
  use BirdSongWeb.ApiConnCase

  alias BirdSong.{
    Bird,
    Quiz,
    Accounts.User
  }

  setup %{user: user} do
    BirdSong.StaticData.seed_taxonomy("test/mock_data")

    {:ok, _} = update_current_quiz(user)
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

  describe "GET /api/v1/users/:user_id/quizzes/current" do
    test "returns current quiz if current quiz is assigned", %{
      conn: conn,
      updated_user: user,
      quiz: quiz
    } do
      assert user.current_quiz_id == quiz.id

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, "current"))
        |> json_response(:ok)

      assert Map.keys(response) == ["quiz"]
    end

    test "returns 404 if user does not have a current quiz assigned", %{
      conn: conn,
      updated_user: user
    } do
      user
      |> User.current_quiz_changeset(%{current_quiz_id: nil})
      |> BirdSong.Repo.update!()

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, "current"))
        |> json_response(:not_found)

      assert response == %{
               "message" => "No current quiz assigned.",
               "error" => true
             }
    end
  end

  describe "GET /api/v1/users/:user_id/quizzes/:quiz_id" do
    test "returns a quiz if it exists", %{conn: conn, user: user, quiz: old_quiz} do
      assert {:ok, %{quiz: _new_quiz}} = update_current_quiz(user)

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
      assert {:ok, %{quiz: new_quiz}} = update_current_quiz(user_fixture())

      response =
        conn
        |> get(Routes.api_v1_user_quiz_path(conn, :show, user.id, new_quiz.id))
        |> json_response(:forbidden)

      assert response == %{"message" => "Access forbidden."}
    end
  end

  defp update_current_quiz(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:user, user)
    |> Ecto.Multi.put(:region_code, "US-NC-067")
    |> Ecto.Multi.all(:birds, Bird)
    |> Quiz.create_and_update_user()
  end
end
