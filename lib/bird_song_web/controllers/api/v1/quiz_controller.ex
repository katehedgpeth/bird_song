defmodule BirdSongWeb.Api.V1.QuizController do
  use BirdSongWeb, :controller

  alias BirdSong.{
    Accounts,
    Bird,
    Quiz
  }

  action_fallback(BirdSongWeb.FallbackController)

  def create(conn, %{} = params) do
    Ecto.Multi.new()
    |> Ecto.Multi.put(:user, conn.assigns.current_user)
    |> Ecto.Multi.put(:region_code, params["region_code"])
    |> Ecto.Multi.all(:birds, birds_query(params))
    |> Quiz.create_and_update_user()
    |> case do
      {:ok, %{quiz: quiz}} ->
        json(conn, %{quiz: quiz})

      {:error, :quiz, changeset, %{}} ->
        conn
        |> put_view(BirdSongWeb.ChangesetView)
        |> put_status(:bad_request)
        |> render("error.json", changeset: changeset)
    end
  end

  defp birds_query(params) do
    params
    |> Map.get("birds", [])
    |> Bird.get_many_by_id_query()
  end
end
