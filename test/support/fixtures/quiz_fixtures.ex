defmodule BirdSong.QuizFixtures do
  alias BirdSong.AccountsFixtures

  alias BirdSong.{
    Bird,
    BirdFixtures,
    Quiz
  }

  @default_region "US-NC"

  @doc """
  Generates a quiz.

  Default values will be generated if not provided:
    user: `AccountsFixtures.user_fixture()`
    birds: `BirdFixtures.random_list(10)`
    region: #{@default_region}
  """
  def quiz_fixture(attrs) do
    {user, attrs} = Map.pop_lazy(attrs, :user, fn -> AccountsFixtures.user_fixture() end)

    Quiz.changeset(
      user,
      attrs
      |> Map.put_new_lazy(:birds, fn -> BirdFixtures.random_list(4) end)
      |> Map.put_new(:region_code, @default_region)
    )
    |> BirdSong.Repo.insert!()
  end

  @doc """
  Generates an answer for a quiz.

  Takes an optional second argument, a boolean indicating whether the answer should be correct.

  If :correct_bird attr is not provided, it will be randomly
  selected from the list of birds from the quiz.
  """
  def answer_fixture(attrs, correct? \\ Enum.random([true, false])) do
    %Quiz{birds: birds} = ensure_preloaded_quiz_birds(attrs.quiz)

    attrs =
      attrs
      |> Map.put_new_lazy(:correct_bird, fn -> Enum.random(birds) end)
      |> set_answer_submitted_bird(correct?: correct?)

    attrs =
      case attrs[:answer_date] do
        nil ->
          attrs

        date ->
          attrs
          |> Map.put(:inserted_at, date)
          |> Map.put(:updated_at, date)
      end

    %{correct_bird: %Bird{}, submitted_bird: %Bird{}, quiz: _} =
      Map.take(attrs, [:correct_bird, :submitted_bird, :quiz])

    Quiz.Answer.submit!(attrs)
  end

  @doc """
  Generates one answer for every bird in a quiz. Can optionally take an argument for the percent
  of answers that should be correct.

  If :quiz attr is not provided, it will be generated using QuizFixtures.quiz_fixture/1.
  """
  def generate_answers(attrs) do
    generate_answers(attrs, 50)
  end

  def generate_answers(%{quiz: _} = attrs, correct_count) do
    %Quiz{birds: birds} = ensure_preloaded_quiz_birds(attrs.quiz)

    birds
    |> Enum.map(&Map.put(attrs, :correct_bird, &1))
    |> Enum.with_index()
    |> Enum.map(fn
      {bird_attrs, idx} -> answer_fixture(bird_attrs, idx < correct_count)
    end)
  end

  def generate_answers(attrs, pct_correct) do
    attrs
    |> Map.put_new_lazy(:quiz, fn -> quiz_fixture(attrs) end)
    |> generate_answers(pct_correct)
  end

  defp ensure_preloaded_quiz_birds(%Quiz{birds: [%Bird{} | _]} = quiz) do
    quiz
  end

  defp ensure_preloaded_quiz_birds(%Quiz{birds: %Ecto.Association.NotLoaded{}} = quiz) do
    BirdSong.Repo.preload(quiz, [:birds])
  end

  defp set_answer_submitted_bird(%{submitted_bird: _} = attrs, _correct?) do
    attrs
  end

  defp set_answer_submitted_bird(%{correct_bird: %Bird{}} = attrs, correct?: true) do
    Map.put(attrs, :submitted_bird, attrs.correct_bird)
  end

  defp set_answer_submitted_bird(%{correct_bird: %Bird{}, quiz: %Quiz{}} = attrs, correct?: false) do
    Map.put_new_lazy(attrs, :submitted_bird, fn ->
      attrs.quiz.birds
      |> Enum.reject(&(&1.id === attrs.correct_bird.id))
      |> Enum.random()
    end)
  end
end
