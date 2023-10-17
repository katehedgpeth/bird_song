defmodule BirdSong.UserQuiz do
  alias BirdSong.{
    Accounts.User,
    Quiz
  }

  def get_quiz(%User{id: user_id}, quiz_id, repo \\ BirdSong.Repo) do
    case repo.get(Quiz, quiz_id) do
      %Quiz{user_id: ^user_id} = quiz -> {:ok, quiz}
      %Quiz{} -> {:error, :not_owned_by_user}
      nil -> {:error, :not_found}
    end
  end
end
