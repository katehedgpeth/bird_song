defmodule BirdSongWeb.Api.V1.QuizAnswersControllerTest do
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

    test "POST /quizzes/:quiz_id/answers", %{conn: conn, quiz: quiz, birds: birds} do
      conn =
        post(
          conn,
          create_path(conn, quiz.id, correct_bird_ids(birds))
        )

      assert json_response(conn, :unauthorized) == %{
               "message" => "Login required."
             }
    end
  end

  describe "POST /quizzes/:quiz_id/answers" do
    test "returns %{answer: _} if post is successful", %{
      birds: birds,
      conn: conn,
      quiz: quiz
    } do
      response =
        conn
        |> post(create_path(conn, quiz.id, correct_bird_ids(birds)))
        |> json_response(:ok)

      assert Map.keys(response) == ["answer"]

      assert Map.keys(response["answer"]) == [
               "correct?",
               "correct_bird",
               "submitted_bird"
             ]

      assert response["answer"]["correct?"] == true
    end

    test "correctly determines that an answer is not correct", %{
      birds: birds,
      conn: conn,
      quiz: quiz
    } do
      path =
        create_path(
          conn,
          quiz.id,
          %{
            correct: bird_id(birds, 0),
            submitted: bird_id(birds, 1)
          }
        )

      response =
        conn
        |> post(path)
        |> json_response(:ok)

      assert response["answer"]["correct?"] == false
    end

    test "returns %{correct_bird: 'not_found'} if correct bird doesn't exist", %{
      conn: conn,
      quiz: quiz,
      birds: birds
    } do
      path = create_path(conn, quiz.id, %{correct: 1, submitted: bird_id(birds, 0)})

      response =
        conn
        |> post(path)
        |> json_response(:bad_request)

      assert response == %{"correct_bird" => "not_found", "error" => true}
    end

    test "returns %{submitted_bird: 'not_found'} if submitted bird doesn't exist", %{
      conn: conn,
      quiz: quiz,
      birds: birds
    } do
      path = create_path(conn, quiz.id, %{correct: bird_id(birds, 0), submitted: 1})

      response =
        conn
        |> post(path)
        |> json_response(:bad_request)

      assert response == %{"submitted_bird" => "not_found", "error" => true}
    end

    test "returns %{quiz: 'not_found'} if quiz doesn't exist", %{
      conn: conn,
      birds: birds
    } do
      path = create_path(conn, 1, correct_bird_ids(birds))

      response =
        conn
        |> post(path)
        |> json_response(:bad_request)

      assert response == %{"quiz" => "not_found", "error" => true}
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

  defp bird_id(birds, idx) do
    birds
    |> Enum.at(idx)
    |> Map.fetch!(:id)
  end

  defp correct_bird_ids(birds) do
    %{
      correct: bird_id(birds, 0),
      submitted: bird_id(birds, 0)
    }
  end

  defp create_path(
         conn,
         quiz_id,
         ids
       ) do
    Routes.api_v1_quiz_answers_path(conn, :create, quiz_id,
      correct_bird: ids[:correct],
      submitted_bird: ids[:submitted]
    )
  end
end
