defmodule BirdSongWeb.QuizLive.Assign do
  require Logger

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias BirdSong.Services
  alias BirdSongWeb.QuizLive.Visibility

  @asset_cdn "https://cdn.download.ams.birds.cornell.edu"

  defstruct [
    # set by Phoenix
    :socket,
    :id,

    # custom assigns
    :current,
    :quiz,
    :services,
    :user,
    asset_cdn: @asset_cdn,
    visibility: %Visibility{}
  ]

  def assigns_to_struct(assigns) do
    assigns
    |> Map.drop([:__changed__, :live_action, :flash, :myself])
    |> Keyword.new()
    |> __struct__()
  end

  def assign(%__MODULE__{} = assigns, %Socket{} = socket) do
    LiveView.assign(socket, Map.from_struct(assigns))
  end

  def on_mount(:assign_services, %{} = params, _session, %Socket{} = socket) do
    assign_services(socket, params)
  end

  def on_mount(
        :assign_services,
        :not_mounted_at_router,
        %{"services" => _} = session,
        %Socket{} = socket
      ) do
    assign_services(socket, session)
  end

  @spec assign_services(Socket.t(), map) :: {:cont | :halt, Socket.t()}
  defp assign_services(%Socket{} = socket, %{"services" => instance_name}) do
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
end
