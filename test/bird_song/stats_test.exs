defmodule BirdSong.StatsTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup

  alias BirdSong.AccountsFixtures

  alias BirdSong.{
    Accounts,
    BirdFixtures,
    Quiz,
    QuizFixtures,
    Stats
  }

  @moduletag pct_correct: 80

  setup :seed_from_mock_taxonomy

  describe "get_counts/1" do
    setup tags do
      # 2:15pm, Thursday, May 18 2023
      today =
        DateTime.new!(
          Date.new!(2023, 5, 18),
          Time.new!(14, 15, 0)
        )

      assert tags[:user] === nil
      user = AccountsFixtures.user_fixture()
      birds = BirdFixtures.random_list(4)

      %{quiz: quiz, user: user} =
        Accounts.update_current_quiz!(user.id, %{
          birds: birds,
          region_code: "US-NC",
          inserted_at: today,
          updated_at: today
        })

      QuizFixtures.generate_answers(
        %{
          user: user,
          quiz: quiz,
          inserted_at: today,
          updated_at: today
        },
        3
      )

      for days_back <- [-1, -6, -27, -350] do
        date = DateTime.add(today, days_back, :day)

        QuizFixtures.generate_answers(
          %{
            user: user,
            inserted_at: date,
            updated_at: date
          },
          3
        )
      end

      all_answers =
        Quiz.Answer
        |> BirdSong.Repo.all()

      {:ok,
       [
         all_answers: all_answers,
         birds: birds,
         user: user,
         today: today
       ]}
    end

    test "calculates all stats for user", tags do
      assert %Accounts.User{} = tags.user

      assert length(tags.birds) === 4

      quizzes = Quiz.get_all_for_user(tags.user)
      assert length(quizzes) === 5

      assert length(tags.all_answers) === 5 * 4
      assert tags.all_answers |> Enum.filter(& &1.correct?) |> length() === 5 * 3

      stats = Stats.get_counts(tags.user.id, tags.today)
      assert %Stats{} = stats

      assert stats.all_time.total === 20
      assert stats.all_time.correct === 15

      assert stats.this_month.total === 12
      assert stats.this_month.correct === 9

      assert stats.this_week.total === 8
      assert stats.this_week.correct === 6

      assert stats.today.total === 4
      assert stats.today.correct === 3

      assert stats.current_quiz.total === 4
      assert stats.current_quiz.correct === 3
    end
  end
end
