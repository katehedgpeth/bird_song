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
    |> Ecto.Multi.put(:params, %{
      birds: Map.get(params, "birds", []),
      region_code: Map.get(params, "region_code"),
      user: conn.assigns.current_user
    })
    |> Ecto.Multi.all(:birds, &birds_query/1)
    |> Ecto.Multi.insert(:quiz, &quiz_changeset/1)
    |> Ecto.Multi.update(:updated_user, &user_changeset/1)
    |> BirdSong.Repo.transaction()
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

  defp birds_query(%{params: %{birds: bird_ids}}) do
    Bird.get_many_by_id_query(bird_ids)
  end

  defp quiz_changeset(%{
         birds: birds,
         params: params
       }) do
    Quiz.changeset(params.user, %{
      birds: birds,
      region_code: params.region_code
    })
  end

  defp user_changeset(%{
         params: %{user: user},
         quiz: %Quiz{id: quiz_id}
       }) do
    Accounts.User.current_quiz_changeset(
      user,
      %{current_quiz_id: quiz_id}
    )
  end
end
