defmodule BirdSongWeb.Api.V1.QuizAnswersController do
  use BirdSongWeb, :controller

  alias BirdSong.{
    Bird,
    Quiz.Answer,
    UserQuiz
  }

  def create(conn, params) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:user, conn.assigns.current_user)
    |> Ecto.Multi.run(:quiz, &get_quiz(&1, &2, Map.fetch!(params, "quiz_id")))
    |> Ecto.Multi.run(:correct_bird, &get_bird(&1, &2, params["correct_bird"]))
    |> Ecto.Multi.run(:submitted_bird, &get_bird(&1, &2, params["submitted_bird"]))
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

  defp get_quiz(repo, %{user: user}, quiz_id) do
    with {:ok, quiz} <- UserQuiz.get_quiz(user, quiz_id, repo) do
      {:ok, repo.preload(quiz, birds: [:family, :order])}
    end
  end

  defp get_bird(repo, %{}, id) do
    Bird
    |> repo.get(id)
    |> repo.preload([:family, :order])
    |> case do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end
end
