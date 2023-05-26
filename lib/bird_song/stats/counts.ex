defmodule BirdSong.Stats.Counts do
  alias BirdSong.Quiz.Answer

  defstruct [:correct, :total]

  @type t() :: %__MODULE__{
          correct: integer(),
          total: integer()
        }

  def calculate(%__MODULE__{correct: correct, total: total}) do
    correct
    |> Kernel./(total)
    |> Kernel.*(100)
    |> Float.round(1)
  end

  def new(answers) when is_list(answers) do
    %__MODULE__{
      total: length(answers),
      correct: Enum.count(answers, & &1.correct?)
    }
  end

  def update_counts(%__MODULE__{} = counts, %Answer{} = answer) do
    %{counts | total: counts.total + 1}
    |> update_correct(answer)
  end

  def update_correct(%__MODULE__{} = counts, answer) do
    case answer do
      %Answer{correct?: true} -> %{counts | correct: counts.correct + 1}
      %Answer{} -> counts
    end
  end
end
