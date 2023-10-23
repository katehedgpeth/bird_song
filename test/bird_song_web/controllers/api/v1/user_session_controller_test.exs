defmodule BirdSongWeb.Api.V1.UserSessionControllerTest do
  use BirdSongWeb.ApiConnCase

  describe "create user session" do
    @tag login?: false
    test "logs in user if password is valid", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.api_v1_user_session_path(conn, :create),
          user: %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        )

      response = json_response(conn, 201)
      assert Map.keys(response) == ["message", "success", "token", "user"]

      assert %{
               "message" => "User successfully logged in.",
               "success" => true,
               "user" => %{"email" => _, "id" => _}
             } = response
    end

    @tag login?: false
    test "returns 401 when password is invalid", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.api_v1_user_session_path(conn, :create),
          user: %{email: user.email, password: "invalid_password"}
        )

      assert json_response(conn, :unauthorized) == %{
               "error" => true,
               "message" => "Invalid email or password."
             }
    end

    test "returns 401 when password is invalid even if session cookie exists", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, Routes.api_v1_user_session_path(conn, :create),
          user: %{email: user.email, password: valid_user_password()}
        )

      conn = fetch_cookies(conn, [])
      assert Map.keys(conn.cookies) == ["_bird_song_key"]

      conn =
        post(conn, Routes.api_v1_user_session_path(conn, :create),
          user: %{email: user.email, password: "invalid_password"}
        )

      assert json_response(conn, :unauthorized)
    end
  end

  describe "log out" do
    test "deletes user session", %{conn: conn} do
      conn = delete(conn, Routes.api_v1_user_session_path(conn, :delete))

      assert json_response(conn, 200) == %{
               "message" => "User logged out successfully.",
               "success" => true
             }

      conn = post(conn, Routes.api_v1_quiz_path(conn, :create))
      assert json_response(conn, :unauthorized) == %{"message" => "Login required."}
    end
  end
end
