defmodule BirdSong.Stats do
  alias BirdSong.{
    Accounts,
    Quiz.Answer,
    Stats.Counts
  }

  defstruct [
    :all_time,
    :current_quiz,
    :this_week,
    :this_month,
    :today
  ]

  @type t() :: %__MODULE__{
          current_quiz: Count.t(),
          today: Count.t()
        }

  def get_counts(user_id, today \\ DateTime.now!("Etc/UTC")) do
    %Accounts.User{answers: answers, current_quiz_id: current_quiz_id} =
      Accounts.get_user!(user_id, preload: [:answers])

    update_struct(%__MODULE__{}, &build_counts(&2, &1, answers, current_quiz_id, today))
  end

  defp build_counts(
         %__MODULE__{} = acc,
         key,
         answers,
         current_quiz_id,
         today
       ) do
    Map.replace!(
      acc,
      key,
      answers
      |> Enum.filter(&include_answer?(key, &1, today, current_quiz_id))
      |> Counts.new()
    )
  end

  defp include_answer?(:all_time, %Answer{}, %DateTime{}, _current_quiz_id) do
    true
  end

  defp include_answer?(:current_quiz, %Answer{quiz_id: quiz_id}, %DateTime{}, current_quiz_id) do
    quiz_id === current_quiz_id
  end

  defp include_answer?(time_range, %Answer{} = answer, %DateTime{} = today, _current_quiz_id) do
    Answer.inserted_on_or_after?(answer, start_of_time_range(time_range, today))
  end

  defp start_of_time_range(:today, today), do: today
  defp start_of_time_range(:this_week, today), do: Date.beginning_of_week(today)
  defp start_of_time_range(:this_month, today), do: Date.beginning_of_month(today)
  defp start_of_time_range(:this_year, %DateTime{year: year}), do: Date.new!(year, 1, 1)

  def update_struct(%__MODULE__{} = struct, callback)
      when is_function(callback, 2) do
    struct
    |> Map.from_struct()
    |> Map.keys()
    |> Enum.reduce(struct, callback)
  end
end
