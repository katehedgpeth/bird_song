defmodule BirdSongWeb.Plugs.AssignQuiz do
  alias Plug.Conn

  alias BirdSong.Quiz

  @behaviour Plug

  @impl Plug
  def init([]), do: []

  @impl Plug
  def call(
        %Conn{params: %{"quiz_id" => quiz_id}, assigns: %{current_user: %{id: user_id}}} = conn,
        []
      ) do
    Quiz
    |> BirdSong.Repo.get(quiz_id)
    |> BirdSong.Repo.preload(birds: [:family, :order])
    |> case do
      %Quiz{user_id: ^user_id} = quiz ->
        Conn.assign(conn, :quiz, quiz)

      %Quiz{} ->
        conn
        |> Conn.put_status(:unauthorized)
        |> Phoenix.Controller.json(%{message: "Quiz not owned by user"})
        |> Conn.halt()

      nil ->
        conn
        |> Conn.put_status(:not_found)
        |> Phoenix.Controller.json(%{message: "Quiz not found"})
        |> Conn.halt()
    end
  end
end
