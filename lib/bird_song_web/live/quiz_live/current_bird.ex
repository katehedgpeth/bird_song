defmodule BirdSongWeb.QuizLive.CurrentBird do
  require Logger
  alias Phoenix.{LiveView, LiveView.Socket}
  alias BirdSong.Bird
  alias BirdSong.Services.{Flickr, XenoCanto}
  alias BirdSongWeb.QuizLive.{Caches, EtsTables}

  defstruct [:bird, :recording, :image]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          recording: XenoCanto.Recording.t() | nil,
          image: Photo.t() | nil
        }

  @spec assign_current_bird(Socket.t(), String.t()) :: Socket.t()
  def assign_current_bird(%Socket{} = socket, "" <> sci_name) do
    case EtsTables.Birds.lookup_bird(socket, sci_name) do
      {:ok, %Bird{} = bird} ->
        LiveView.assign(
          socket,
          :current_bird,
          %__MODULE__{bird: bird}
          |> do_update_recording(socket)
          |> do_update_image(socket)
        )
    end
  end

  @spec update_recording(Socket.t()) :: Socket.t()
  def update_recording(%Socket{} = socket) do
    LiveView.assign(
      socket,
      :current_bird,
      socket
      |> get_data()
      |> do_update_recording(socket)
    )
  end

  def update_image(%Socket{} = socket) do
    LiveView.assign(
      socket,
      :current_bird,
      socket
      |> get_data()
      |> do_update_image(socket)
    )
  end

  @spec do_update_recording(t(), Socket.t()) :: t()
  defp do_update_recording(
         %__MODULE__{} = data,
         %Socket{} = socket
       ) do
    case Caches.get_recordings(socket, data.bird) do
      {:ok, %XenoCanto.Response{recordings: recordings}} ->
        %{data | recording: Enum.random(recordings)}

      _ ->
        data
    end
  end

  defp do_update_image(%__MODULE__{bird: %Bird{} = bird} = data, %Socket{} = socket) do
    case Caches.get_images(socket, bird) do
      {:ok, %Flickr.Response{photos: images}} ->
        Map.replace!(data, :image, Enum.random(images))

      response ->
        Logger.error("unexpected response from get_images\n" <> inspect(response))
        data
    end
  end

  defp get_data(%Socket{assigns: %{current_bird: %__MODULE__{} = data}}), do: data
end
