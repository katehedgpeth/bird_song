defmodule BirdSongWeb.Api.V1.QuizController do
  use BirdSongWeb, :controller

  alias Plug.Conn

  alias BirdSong.{
    Bird,
    Quiz
  }

  action_fallback(BirdSongWeb.FallbackController)

  def create(conn, %{} = params) do
    Ecto.Multi.new()
    |> Ecto.Multi.all(:birds, birds_query(params))
    |> Ecto.Multi.insert(:quiz, &quiz_changeset(&1, conn, params))
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

  defp birds_query(params) do
    params
    |> Map.get("birds", [])
    |> Bird.get_many_by_id_query()
  end

  defp quiz_changeset(%{birds: birds}, %Conn{assigns: %{current_user: user}}, params) do
    Quiz.changeset(user, %{
      birds: birds,
      region_code: params["region_code"]
    })
  end
end
