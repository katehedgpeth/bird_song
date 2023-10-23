defmodule BirdSong.Accounts.GuardianErrorHandler do
  import Plug.Conn

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {:unauthenticated, _reason}, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{message: "Login required."})
  end
end
