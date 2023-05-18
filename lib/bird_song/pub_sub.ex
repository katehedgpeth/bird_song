defmodule BirdSong.PubSub.UserTokenError do
  use BirdSong.CustomError, [:assigns]

  def message_text(%__MODULE__{assigns: assigns}) do
    """
    BirdSong.PubSub.on_mount expects callers to have a :user assign, which should be
    a map that contains a :token key

    received:
    #{assigns |> Enum.map(&inspect/1) |> Enum.join("\n")}
    """
  end
end

defmodule BirdSong.PubSub do
  alias BirdSong.{
    PubSub.UserTokenError
  }

  alias Phoenix.LiveView.Socket
  alias Phoenix.PubSub

  def on_mount(
        :subscribe,
        _params_or_not_mounted_at_router,
        %{},
        %Socket{assigns: %{user: %{}}} = socket
      ) do
    {:cont, subscribe(socket)}
  end

  def broadcast(%Socket{} = socket, message) do
    _ = PubSub.broadcast(__MODULE__, session_topic(socket), message)

    socket
  end

  def subscribe(%{} = socket_or_conn) do
    :ok = PubSub.subscribe(__MODULE__, session_topic(socket_or_conn))
    socket_or_conn
  end

  defp session_topic(%{assigns: %{user: %{token: token}}}) do
    "user:#{token}"
  end

  defp session_topic(%{assigns: assigns}) do
    raise UserTokenError.exception(assigns: assigns)
  end
end
