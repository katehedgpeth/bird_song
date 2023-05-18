defmodule BirdSongWeb.QuizLive.User do
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Accounts,
    Accounts.User
  }

  def on_mount(
        :default,
        _params_or_not_mounted_at_router,
        %{"user_token" => token},
        %Socket{} = socket
      ) do
    case Accounts.get_user_by_session_token(token) do
      %User{id: id} ->
        {:cont, Phoenix.LiveView.assign(socket, :user, %{token: token, id: id})}

      nil ->
        redirect(socket)
    end
  end

  def on_mount(
        :default,
        _params_or_not_mounted_at_router,
        %{},
        %Socket{} = socket
      ) do
    redirect(socket)
  end

  defp redirect(%Socket{} = socket) do
    {:halt, Phoenix.LiveView.redirect(socket, to: "/quiz/new")}
  end
end
