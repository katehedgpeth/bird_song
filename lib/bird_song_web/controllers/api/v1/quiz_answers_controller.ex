defmodule BirdSongWeb.Api.V1.QuizAnswersController do
  use BirdSongWeb, :controller

  alias BirdSong.{
    Quiz.Answer
  }

  plug BirdSongWeb.Plugs.AssignQuiz
  plug BirdSongWeb.Plugs.AssignQuizBird, assign_to: :bird
  plug BirdSongWeb.Plugs.AssignQuizBird, assign_to: :submitted_bird

  def create(conn, %{}) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:user, conn.assigns.current_user)
    |> Ecto.Multi.put(:quiz, conn.assigns.quiz)
    |> Ecto.Multi.put(:correct_bird, conn.assigns.bird)
    |> Ecto.Multi.put(:submitted_bird, conn.assigns.submitted_bird)
    |> Ecto.Multi.insert(:answer, &Answer.changeset/1)
    |> BirdSong.Repo.transaction()
    |> case do
      {:ok, %{answer: answer}} ->
        json(conn, %{answer: answer})

      {:error, :answer, changeset, %{}} ->
        conn
        |> put_view(BirdSongWeb.ChangesetView)
        |> render("error.json", %{changeset: changeset})

      {:error, item, :not_found, %{}} ->
        conn
        |> put_status(:bad_request)
        |> json(Map.put(%{error: true}, item, :not_found))
    end
  end
end
