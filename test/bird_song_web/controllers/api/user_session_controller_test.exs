defmodule BirdSongWeb.Api.UserControllerTest do
  use BirdSongWeb.ConnCase

  import BirdSong.AccountsFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json"), user: user_fixture()}
  end

  def api_path(conn, method, params \\ []) do
    Path.join(
      "/api",
      Routes.user_session_path(conn, method, params)
    )
  end

  describe "create user session" do
    test "logs in user if password is valid", %{conn: conn, user: user} do
      conn =
        post(conn, api_path(conn, :create),
          user: %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        )

      assert json_response(conn, 201) == %{
               "message" => "User successfully logged in.",
               "success" => true
             }
    end

    test "returns 401 when password is invalid", %{conn: conn, user: user} do
      conn =
        post(conn, api_path(conn, :create),
          user: %{email: user.email, password: "invalid_password"}
        )

      assert json_response(conn, :unauthorized) == %{
               "error" => true,
               "message" => "Invalid email or password."
             }
    end
  end

  describe "log out" do
    test "deletes user session", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(api_path(conn, :delete))

      assert json_response(conn, 200) == %{
               "message" => "User logged out successfully.",
               "success" => true
             }

      conn = post(conn, Routes.quiz_path(conn, :create))
      assert json_response(conn, :unauthorized) == %{"message" => "Login required."}
    end
  end
end
