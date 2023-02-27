defmodule BirdSongWeb.QuizLive.CurrentBird do
  alias Phoenix.{LiveView, LiveView.Socket}
  alias BirdSong.Bird
  alias BirdSong.Services.XenoCanto
  alias BirdSong.Services.Flickr.Photo
  alias BirdSongWeb.QuizLive.{Caches, EtsTables}

  defstruct [:bird, :recording, :image]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          recording: XenoCanto.Recording.t(),
          image: Photo.t()
        }

  @spec assign_current_bird(Socket.t(), String.t()) :: Socket.t()
  def assign_current_bird(%Socket{} = socket, "" <> sci_name) do
    LiveView.assign(socket, :current_bird, get_bird_and_data(socket, sci_name))
  end

  @spec update_recording(Socket.t()) :: Socket.t()
  def update_recording(%Socket{} = socket) do
    %Socket{assigns: %{current_bird: data}} = socket

    LiveView.assign(
      socket,
      :current_bird,
      do_update_recording(data, socket)
    )
  end

  @spec get_bird_and_data(Socket.t(), String.t()) :: t()
  defp get_bird_and_data(%Socket{} = socket, "" <> sci_name) do
    {:ok, bird} = EtsTables.Birds.lookup_bird(socket, sci_name)

    %__MODULE__{bird: bird}
    |> do_update_recording(socket)
  end

  @spec do_update_recording(t(), Socket.t()) :: t()
  defp do_update_recording(%__MODULE__{bird: %Bird{} = bird} = data, %Socket{} = socket) do
    case Caches.get_recordings(socket, bird) do
      {:ok, %XenoCanto.Response{recordings: recordings}} ->
        Map.replace!(
          data,
          :recording,
          Enum.random(recordings)
        )
    end
  end
end
