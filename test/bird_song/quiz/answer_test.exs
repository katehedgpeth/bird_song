defmodule BirdSong.Quiz.AnswerTest do
  use BirdSong.DataCase

  alias Ecto.InvalidChangesetError
  alias BirdSong.Quiz

  alias BirdSong.{
    Accounts,
    AccountsFixtures,
    Bird,
    Quiz.Answer,
    QuizFixtures
  }

  import BirdSong.TestSetup

  setup [:seed_from_mock_taxonomy]

  describe "&submit/1" do
    setup tags do
      %{
        quiz:
          tags
          |> QuizFixtures.quiz_fixture()
          |> BirdSong.Repo.preload([:birds, :user])
      }
    end

    test "calculates :correct? on its own", %{quiz: quiz} do
      assert %{birds: [bird_1, bird_2 | _]} = quiz

      answer =
        Answer.submit!(%{
          correct_bird: bird_1,
          submitted_bird: bird_2,
          quiz: quiz
        })

      assert %Answer{} = answer
      assert answer.correct? === false

      answer = Answer.submit!(%{correct_bird: bird_1, submitted_bird: bird_1, quiz: quiz})
      assert %Answer{} = answer
      assert answer.correct? === true
    end

    test "raises an error if :submitted_bird is missing", %{quiz: quiz} do
      assert %{birds: [bird | _]} = quiz
      params = %{correct_bird: bird, quiz: quiz}

      error =
        assert_raise InvalidChangesetError, fn ->
          Answer.submit!(params)
        end

      assert %InvalidChangesetError{changeset: %{errors: errors}} = error
      assert [submitted_bird: {_, [validation: :required]}] = errors
    end

    test "raises an error if :correct_bird is missing", %{quiz: quiz} do
      assert %{birds: [bird | _]} = quiz
      params = %{submitted_bird: bird, quiz: quiz}

      error =
        assert_raise InvalidChangesetError, fn ->
          Answer.submit!(params)
        end

      assert %InvalidChangesetError{changeset: %{errors: errors}} = error
      assert [correct_bird: {_, [validation: :required]}] = errors
    end

    test "raises an error if :quiz is missing", %{} do
      bird = BirdSong.Repo.all(Bird) |> Enum.at(0)
      params = %{submitted_bird: bird, correct_bird: bird}

      assert_raise InvalidChangesetError, fn ->
        Answer.submit!(params)
      end
    end
  end

  describe "inserted_on_or_after?/2" do
    setup [:generate_answers]

    setup do
      now = DateTime.now!("Etc/UTC")
      days_ago_3 = DateTime.add(now, -3, :day)
      days_ago_7 = DateTime.add(now, -7, :day)
      {:ok, now: now, days_ago: %{7 => days_ago_7, 3 => days_ago_3}}
    end

    test "returns true if answer was inserted on the given date",
         tags do
      answer = QuizFixtures.answer_fixture(tags)
      assert NaiveDateTime.diff(answer.inserted_at, DateTime.to_naive(tags.now), :second) === 0

      assert Answer.inserted_on_or_after?(answer, tags.now) === true
    end

    test "returns true if answer was inserted after the given date", tags do
      answer =
        tags
        |> Map.put(:answer_date, tags.days_ago[3])
        |> QuizFixtures.answer_fixture()

      assert Answer.inserted_on_or_after?(answer, tags.days_ago[7]) === true
    end

    test "returns false if answer was inserted before the given date", tags do
      answer =
        tags
        |> Map.put(:answer_date, tags.days_ago[7])
        |> QuizFixtures.answer_fixture()

      assert Date.compare(answer.inserted_at, tags.days_ago[7]) === :eq

      assert Answer.inserted_on_or_after?(answer, tags.days_ago[3]) === false
    end
  end

  describe "&all_for_quiz/1" do
    setup [:generate_answers]

    test "returns all answers for quiz", %{
      quiz: quiz_1,
      answers: answers
    } do
      assert %{quiz: quiz_2, answers: answers_2} =
               generate_answers(%{
                 user: AccountsFixtures.user_fixture(),
                 bird_count: 4
               })

      fetched = Answer.get_for_quiz(quiz_1.id)
      assert [%Answer{} | _] = fetched

      for answer <- fetched do
        assert answer.quiz_id === quiz_1.id
      end

      assert MapSet.new(answers, & &1.id) === MapSet.new(fetched, & &1.id)

      fetched = Answer.get_for_quiz(quiz_2.id)
      assert MapSet.new(answers_2, & &1.id) === MapSet.new(fetched, & &1.id)
    end
  end

  describe "&get_all_for_user/1" do
    setup [:generate_answers]

    test "returns a list of all answers that a user has ever submitted", %{
      user: user,
      answers: answers_1
    } do
      assert %{answers: answers_2} =
               %{user: user, bird_count: 4}
               |> generate_answers()

      assert {:ok, %{all_answers_for_user: answers}} =
               Answer.get_all_for_user(%{user: user})
               |> BirdSong.Repo.transaction()

      assert [%Answer{} | _] = answers

      assert same_ids?(answers, answers_1 ++ answers_2)
    end

    test "works as part of an Ecto.Multi chain", %{user: user, answers: answers} do
      assert %Accounts.User{id: user_id} = user

      assert {:ok, %{user: _, all_answers_for_user: all_answers}} =
               Ecto.Multi.new()
               |> Ecto.Multi.one(:user, from(Accounts.User, where: [id: ^user_id]))
               |> Ecto.Multi.merge(Answer, :get_all_for_user, [])
               |> BirdSong.Repo.transaction()

      assert same_ids?(answers, all_answers)
    end
  end

  defp same_ids?(list_1, list_2) do
    list_1
    |> MapSet.new(& &1.id)
    |> MapSet.equal?(MapSet.new(list_2, & &1.id))
  end

  defp generate_answers(tags) do
    answers = BirdSong.QuizFixtures.generate_answers(tags)

    quiz =
      Quiz
      |> BirdSong.Repo.get!(List.first(answers).quiz_id)
      |> Repo.preload([:birds, :user])

    %{
      answers: answers,
      quiz: quiz,
      user: quiz.user
    }
  end
end
