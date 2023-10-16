defmodule BirdSongWeb.Api.V1.UserSessionController do
  use BirdSongWeb, :controller

  alias BirdSongWeb.UserAuth

  action_fallback BirdSongWeb.FallbackController

  def create(conn, %{"user" => user_params}) do
    conn = UserAuth.log_in_user_if_valid_password(conn, user_params)

    case get_session(conn, :user_token) do
      "" <> _ ->
        conn
        |> put_status(:created)
        |> json(%{success: true, message: "User successfully logged in."})

      nil ->
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
