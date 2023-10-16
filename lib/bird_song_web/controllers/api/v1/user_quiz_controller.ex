defmodule BirdSongWeb.Api.V1.UserQuizController do
  use BirdSongWeb, :controller

  alias Plug.Conn

  alias BirdSong.{
    Accounts.User,
    Quiz
  }

  def show(
        %Conn{
          assigns: %{
            current_user: %User{current_quiz_id: nil}
          }
        } = conn,
        %{"quiz_id" => "current"}
      ) do
    conn
    |> put_status(404)
    |> json(%{error: true, message: "No current quiz assigned."})
  end

  def show(conn, %{"quiz_id" => "current"} = params) do
    show(conn, Map.replace!(params, "quiz_id", conn.assigns.current_user.current_quiz_id))
  end

  def show(%Conn{assigns: %{current_user: %{id: user_id}}} = conn, %{"quiz_id" => quiz_id}) do
    with %Quiz{user_id: ^user_id} = quiz <- BirdSong.Repo.get(Quiz, quiz_id) do
      json(conn, %{
        quiz: BirdSong.Repo.preload(quiz, birds: [:family, :order])
      })
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{message: "Quiz not found."})

      %Quiz{} ->
        conn
        |> put_status(:forbidden)
        |> json(%{message: "Access forbidden."})
    end
  end
end
