defmodule BirdSongWeb.SupervisedLiveCase do
  use ExUnit.CaseTemplate

  using opts do
    path = Keyword.get(opts, :path)

    quote bind_quoted: [path: path] do
      use BirdSong.SupervisedCase
      use BirdSongWeb.ConnCase
      import Phoenix.LiveViewTest

      @path path

      if @path do
        setup [
          :path_with_services_query,
          :maybe_login,
          :maybe_load_view
        ]

        defp path_with_services_query(%{test: test}) do
          {:ok, path_with_query: Path.join(@path, "?services=#{test}")}
        end

        defp maybe_login(%{login?: false} = tags) do
          {:ok, load_view?: false}
        end

        defp maybe_login(%{} = tags) do
          {:ok, register_and_log_in_user(tags)}
        end

        defp maybe_load_view(%{login?: false}) do
          :ok
        end

        defp maybe_load_view(%{load_view?: false}) do
          :ok
        end

        defp maybe_load_view(%{conn: conn, path_with_query: path}) do
          assert {:ok, view, html} = Phoenix.LiveViewTest.live(conn, path)

          {:ok, view: view, html: html}
        end
      end
    end
  end
end
