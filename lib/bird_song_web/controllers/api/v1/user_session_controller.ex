defmodule BirdSongWeb.Api.V1.UserSessionController do
  use BirdSongWeb, :controller

  alias Plug.Conn

  alias BirdSongWeb.UserAuth
  alias BirdSong.Accounts.User

  action_fallback BirdSongWeb.FallbackController

  def create(conn, %{"user" => user_params}) do
    case UserAuth.log_in_user_if_valid_password(conn, user_params) do
      %Conn{assigns: %{current_user: %User{}}} = conn ->
        conn
        |> put_status(:created)
        |> json(%{
          success: true,
          message: "User successfully logged in.",
          user: conn.assigns.current_user
        })

      %Conn{} = conn ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: true, message: "Invalid email or password."})
    end
  end

  def delete(conn, %{}) do
    conn
    |> UserAuth.log_out_user()
    |> json(%{success: true, message: "User logged out successfully."})
  end
end
