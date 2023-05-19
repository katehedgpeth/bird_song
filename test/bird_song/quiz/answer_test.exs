defmodule BirdSong.Quiz.AnswerTest do
  use BirdSong.DataCase

  alias BirdSong.{
    Accounts,
    AccountsFixtures,
    Bird,
    Quiz.Answer
  }

  import BirdSong.TestSetup

  @moduletag bird_count: 2

  setup [:seed_from_mock_taxonomy, :get_x_birds, :create_user, :create_quiz]

  defp get_x_birds(%{bird_count: :random} = tags) do
    tags
    |> Map.replace!(:bird_count, random_in_range(1..20))
    |> get_x_birds()
  end

  defp get_x_birds(tags) do
    birds =
      BirdSong.Bird
      |> BirdSong.Repo.all()
      |> Enum.shuffle()
      |> Enum.take(tags.bird_count)

    assert [%Bird{} | _] = birds
    Map.put(tags, :birds, birds)
  end

  defp create_user(%{} = tags) do
    Map.put(tags, :user, AccountsFixtures.user_fixture())
  end

  defp create_quiz(tags) do
    Map.merge(
      tags,
      Accounts.update_current_quiz!(tags.user.id, %{
        birds: tags.birds,
        region_code: "US-NC"
      })
    )
  end

  describe "&submit/1" do
    test "calculates :correct? on its own", %{birds: [bird_1, bird_2], quiz: quiz} do
      answer = Answer.submit!(%{correct_bird: bird_1, submitted_bird: bird_2, quiz: quiz})
      assert %Answer{} = answer
      assert answer.correct? === false

      answer = Answer.submit!(%{correct_bird: bird_1, submitted_bird: bird_1, quiz: quiz})
      assert %Answer{} = answer
      assert answer.correct? === true
    end

    test "raises an error if submitted_bird is missing", %{birds: [bird | _], quiz: quiz} do
      params = %{correct_bird: bird, quiz: quiz}

      error =
        assert_raise KeyError, fn ->
          Answer.submit!(params)
        end

      assert %KeyError{key: :submitted_bird, term: ^params} = error
    end

    test "raises an error if :correct_bird is missing", %{birds: [bird, _], quiz: quiz} do
      params = %{submitted_bird: bird, quiz: quiz}

      error =
        assert_raise KeyError, fn ->
          Answer.submit!(params)
        end

      assert %KeyError{key: :correct_bird, term: ^params} = error
    end

    test "raises an error if :quiz is missing", %{birds: [bird, _]} do
      params = %{submitted_bird: bird, correct_bird: bird}

      assert_raise Ecto.InvalidChangesetError, fn ->
        Answer.submit!(params)
      end
    end
  end

  defp random_in_range(max) do
    max
    |> Range.new(0)
    |> Enum.random()
  end

  defp random_index(list) do
    list
    |> length()
    |> Kernel.-(1)
    |> random_in_range()
  end

  defp pick_random(list) do
    Enum.at(list, random_index(list))
  end

  defp generate_answer(tags) do
    Answer.submit!(%{
      quiz: tags.quiz,
      submitted_bird: pick_random(tags.birds),
      correct_bird: pick_random(tags.birds)
    })
  end

  defp generate_answers(tags) do
    Map.put(
      tags,
      :answers,
      tags.birds
      |> length()
      |> Range.new(1)
      |> Enum.map(fn _ -> generate_answer(tags) end)
    )
  end

  describe "&all_for_quiz/1" do
    setup [:generate_answers]

    test "returns all answers for quiz", %{
      quiz: quiz_1,
      answers: answers
    } do
      assert %{quiz: quiz_2, answers: answers_2} =
               %{user: AccountsFixtures.user_fixture(), bird_count: 4}
               |> get_x_birds()
               |> create_quiz()
               |> generate_answers()

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
end
