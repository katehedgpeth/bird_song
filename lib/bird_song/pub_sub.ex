defmodule BirdSong.PubSub.SessionIdError do
  use BirdSong.CustomError, [:assigns]

  def message_text(%__MODULE__{assigns: assigns}) do
    """
    BirdSong.PubSub expects its subscribers to have a :session_id assign.
    Call `on_mount {BirdSong.PubSub, :subscribe}` at the top of a LiveComponent.

    assigns:
    #{Enum.map(assigns, &inspect/1) |> Enum.join("\n")}
    """
  end
end

defmodule BirdSong.PubSub do
  alias BirdSong.PubSub.SessionIdError
  alias Phoenix.LiveView.Socket
  alias Phoenix.PubSub

  def on_mount(:subscribe, _params_or_not_mounted_at_router, %{} = session, %Socket{} = socket) do
    socket = assign_session_id(socket, session)
    :ok = PubSub.subscribe(__MODULE__, session_topic(socket))
    {:cont, socket}
  end

  def broadcast(%Socket{} = socket, message) do
    _ = PubSub.broadcast(__MODULE__, session_topic(socket), message)

    socket
  end

  defp assign_session_id(%Socket{} = socket, %{"_csrf_token" => "" <> session_id}) do
    Phoenix.LiveView.assign(socket, :session_id, session_id)
  end

  if Mix.env() === :test do
    defp assign_session_id(%Socket{} = socket, %{}) do
      Phoenix.LiveView.assign(socket, :session_id, Ecto.UUID.generate())
    end
  end

  defp session_topic(%Socket{assigns: %{session_id: session_id}}) do
    "session:" <> session_id
  end

  defp session_topic(%Socket{} = socket) do
    raise SessionIdError.exception(assigns: socket.assigns)
  end
end
