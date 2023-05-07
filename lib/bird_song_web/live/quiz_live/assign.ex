defmodule BirdSongWeb.QuizLive.Assign do
  require Logger

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias BirdSong.Services

  defmacro __using__(_ \\ []) do
    quote do
      alias Phoenix.{LiveView, LiveView.Socket}
      import LiveView, only: [assign: 3, assign_new: 3]
      import BirdSongWeb.QuizLive.Assign
    end
  end

  def on_mount(:assign_services, %{} = params, _session, %Socket{} = socket) do
    assign_services(socket, params)
  end

  @spec assign_services(Socket.t(), map) :: {:cont | :halt, Socket.t()}
  defp assign_services(%Socket{} = socket, %{"service_instance_name" => instance_name}) do
    instance_name
    |> get_services_instance_name()
    |> do_assign_services(socket)
  end

  defp assign_services(%Socket{} = socket, %{}) do
    do_assign_services({:ok, Services}, socket)
  end

  defp do_assign_services({:ok, instance_name}, %Socket{} = socket) when is_atom(instance_name) do
    case Services.all(instance_name) do
      %Services{} = services ->
        {:cont, LiveView.assign(socket, :services, services)}

      {:error, :not_alive} ->
        Logger.warn("HALTING BECAUSE SERVICES INSTANCE IS NOT ALIVE: #{instance_name}")
        {:halt, socket}
    end
  end

  defp get_services_instance_name(name) do
    try do
      {:ok, String.to_existing_atom(name)}
    rescue
      ArgumentError ->
        :error
    end
  end

  def get_assign(%Socket{assigns: assigns}, key) do
    Map.fetch!(assigns, key)
  end

  def assign_session_id(%Socket{} = socket, %{"_csrf_token" => "" <> session_id}) do
    Phoenix.LiveView.assign(socket, :session_id, session_id)
  end

  def assign_session_id(%Socket{} = socket, %{}) do
    LiveView.assign(socket, :session_id, nil)
  end
end
