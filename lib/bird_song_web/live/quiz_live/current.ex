defmodule BirdSongWeb.QuizLive.Current do
  require Logger
  use BirdSongWeb.QuizLive.Assign
  alias BirdSong.Services.MacaulayLibrary
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Bird,
    Quiz,
    Services.Flickr,
    Services.Flickr.Photo,
    Services.MacaulayLibrary.Recording
  }

  alias BirdSongWeb.QuizLive

  defstruct [:bird, :recording, :image]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          image: Flickr.Photo.t(),
          recording: MacaulayLibrary.Recording.t()
        }

  def reset(%Socket{} = socket) do
    assign(socket, :current, %__MODULE__{})
  end

  def assign_current(%Socket{} = socket) do
    %__MODULE__{bird: nil} = get_current(socket)
    %Quiz{birds: birds} = QuizLive.Assign.get_assign(socket, :quiz)
    bird = Enum.random(birds)

    socket
    |> assign(:current, %__MODULE__{bird: bird})
    |> update_resource(:recording)
    |> update_resource(:image)
    |> case do
      %Socket{
        assigns: %{
          current: %__MODULE__{
            bird: %Bird{},
            recording: %Recording{},
            image: %Photo{}
          }
        }
      } = socket ->
        socket
    end
  end

  defguard is_resource_key(key) when key in [:recording, :image]

  def update_resource(%Socket{} = socket, resource_key) when is_resource_key(resource_key) do
    update_resource(socket, get_current(socket, :bird), resource_key)
  end

  def update_resource(%Socket{} = socket, %Bird{} = bird, resource_key)
      when is_resource_key(resource_key) do
    plural = :"#{resource_key}s"

    worker = get_worker(socket, plural)

    resource =
      case apply(worker.module, :get, [bird, worker]) do
        {:ok, saved_response} ->
          saved_response
          |> Map.fetch!(plural)
          |> Enum.random()
      end

    assign(
      socket,
      :current,
      socket
      |> get_current()
      |> Map.replace!(resource_key, resource)
    )
  end

  def get_current(%Socket{} = socket) do
    get_assign(socket, :current)
  end

  def get_current(%Socket{} = socket, key) do
    socket
    |> get_current()
    |> Map.fetch!(key)
  end

  defp get_worker(%Socket{assigns: assigns}, key) do
    assigns
    |> Map.fetch!(:services)
    |> Map.fetch!(key)
    |> Map.fetch!(get_worker_key(key))
  end

  defp get_worker_key(:images), do: :PhotoSearch
  defp get_worker_key(:recordings), do: :Recordings
end
