defmodule BirdSongWeb.SupervisedLiveCase do
  alias Plug.CSRFProtection
  use ExUnit.CaseTemplate

  using opts do
    path = Keyword.get(opts, :path)

    quote bind_quoted: [path: path] do
      use BirdSong.SupervisedCase
      use BirdSongWeb.ConnCase
      import Phoenix.LiveViewTest

      @path path

      if @path do
        setup %{conn: conn, test: test} do
          path_with_query =
            Path.join(
              @path,
              "?services=#{test}"
            )

          {:ok, view, html} = Phoenix.LiveViewTest.live(conn, path_with_query)

          {:ok, view: view, html: html, conn: conn}
        end
      end
    end
  end
end
