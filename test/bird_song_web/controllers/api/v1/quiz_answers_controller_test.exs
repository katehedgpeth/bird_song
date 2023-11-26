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
      assert send_request(%{
               conn: conn,
               quiz_id: quiz.id,
               bird_ids: correct_bird_ids(birds),
               expected: :unauthorized
             }) == %{
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
        send_request(%{
          conn: conn,
          quiz_id: quiz.id,
          bird_ids: correct_bird_ids(birds),
          expected: :ok
        })

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
      response =
        send_request(%{
          conn: conn,
          quiz_id: quiz.id,
          bird_ids: %{
            bird_id: bird_id(birds, 0),
            submitted_bird_id: bird_id(birds, 1)
          },
          expected: :ok
        })

      assert response["answer"]["correct?"] == false
    end

    test "returns %{correct_bird: 'not_found'} if correct bird doesn't exist", %{
      conn: conn,
      quiz: quiz,
      birds: birds
    } do
      bird_ids = %{
        bird_id: 1,
        submitted_bird_id: bird_id(birds, 0)
      }

      response =
        send_request(%{
          conn: conn,
          quiz_id: quiz.id,
          bird_ids: bird_ids,
          expected: :bad_request
        })

      assert response["message"] =~ "does not include a bird with id"
    end

    test "returns error if submitted bird doesn't exist", %{
      conn: conn,
      quiz: quiz,
      birds: birds
    } do
      bird_ids = %{
        bird_id: bird_id(birds, 0),
        submitted_bird_id: 1
      }

      response =
        send_request(%{
          conn: conn,
          quiz_id: quiz.id,
          bird_ids: bird_ids,
          expected: :bad_request
        })

      assert response["message"] =~ "does not include a bird with id"
    end

    test "returns %{quiz: 'not_found'} if quiz doesn't exist", %{
      conn: conn,
      birds: birds
    } do
      assert send_request(%{
               conn: conn,
               quiz_id: 1,
               bird_ids: correct_bird_ids(birds),
               expected: :not_found
             }) == %{"message" => "Quiz not found"}
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
      bird_id: bird_id(birds, 0),
      submitted_bird_id: bird_id(birds, 0)
    }
  end

  defp send_request(%{
         conn: conn,
         expected: expected,
         quiz_id: quiz_id,
         bird_ids: bird_ids
       }) do
    conn
    |> post(create_path(conn, quiz_id, bird_ids), post_body(bird_ids))
    |> json_response(expected)
  end

  defp post_body(%{submitted_bird_id: id}) do
    %{submitted_bird_id: id}
  end

  defp create_path(
         conn,
         quiz_id,
         ids
       ) do
    Routes.api_v1_quiz_answers_path(
      conn,
      :create,
      quiz_id,
      ids[:bird_id]
      # correct_bird: ids[:correct],
      # submitted_bird: ids[:submitted]
    )
  end
end
