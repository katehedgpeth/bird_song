defmodule BirdSongWeb.ApiConnCase do
  use ExUnit.CaseTemplate
  alias Plug.Conn
  alias BirdSong.AccountsFixtures

  using do
    quote do
      use BirdSongWeb.ConnCase

      import BirdSong.AccountsFixtures
      alias BirdSongWeb.Router.Helpers, as: Routes

      setup tags do
        {
          :ok,
          login?: tags[:login?] !== false,
          conn: Conn.put_req_header(tags.conn, "accept", "application/json"),
          user: AccountsFixtures.user_fixture()
        }
      end

      setup [:maybe_login]

      def maybe_login(%{login?: false}) do
        :ok
      end

      def maybe_login(%{login?: true, conn: conn, user: user}) do
        %{
          conn: BirdSongWeb.ConnCase.log_in_user(conn, user)
        }
      end
    end
  end
end
