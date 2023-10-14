defmodule BirdSongWeb.UserSessionController do
  use BirdSongWeb, :controller

  alias BirdSongWeb.UserAuth

  def new(conn, _params) do
    render(conn, "new.html", error_message: nil)
  end

  def create(conn, %{"user" => user_params}) do
    redirect_path = UserAuth.session_redirect_path(conn)
    conn = UserAuth.log_in_user_if_valid_password(conn, user_params)

    case get_session(conn, :user_token) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> render("new.html", error_message: "Invalid email or password.")

      "" <> _ ->
        redirect(conn, to: redirect_path)
    end
  end

  def delete(conn, _params) do
    conn
    |> UserAuth.log_out_user()
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: "/")
  end
end
