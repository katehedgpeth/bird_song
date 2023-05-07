defmodule BirdSongWeb.SupervisedLiveCase do
  use ExUnit.CaseTemplate

  using opts do
    path = Keyword.fetch!(opts, :path)

    quote bind_quoted: [path: path] do
      use BirdSong.SupervisedCase
      use BirdSongWeb.ConnCase
      import Phoenix.LiveViewTest

      @path path

      setup %{conn: conn, test: test} do
        path_with_query =
          Path.join(
            @path,
            "?service_instance_name=#{test}"
          )

        # setup session_id
        conn = get(conn, @path)

        {:ok, view, html} =
          Phoenix.LiveViewTest.live(
            conn,
            path_with_query
          )

        {:ok, view: view, html: html, conn: conn}
      end
    end
  end
end
