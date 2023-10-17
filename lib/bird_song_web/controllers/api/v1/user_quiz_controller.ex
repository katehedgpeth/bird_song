defmodule BirdSongWeb.Api.V1.UserQuizController do
  use BirdSongWeb, :controller

  alias BirdSong.{
    UserQuiz
  }

  def show(conn, %{"quiz_id" => quiz_id}) do
    case UserQuiz.get_quiz(conn.assigns.current_user, quiz_id) do
      {:ok, quiz} ->
        json(conn, %{quiz: BirdSong.Repo.preload(quiz, birds: [:family, :order])})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Quiz not found."})

      {:error, :not_owned_by_user} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "Access forbidden."})
    end
  end
end
