defmodule BirdSongWeb.QuizLive.Current do
  require Logger
  alias BirdSong.Services.MacaulayLibrary

  alias BirdSong.{
    Bird,
    Quiz,
    Services.Flickr
  }

  alias BirdSongWeb.{
    QuizLive.Assign
  }

  defstruct [:bird, :recording, :image]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          image: Flickr.Photo.t(),
          recording: MacaulayLibrary.Recording.t()
        }

  def reset(%Assign{} = assigns) do
    Map.put(assigns, :current, %__MODULE__{})
  end

  def assign_current(%Assign{} = assigns) do
    %__MODULE__{bird: nil} = assigns.current
    %Quiz{birds: birds} = assigns.quiz
    bird = Enum.random(birds)

    assigns
    |> Map.put(:current, %__MODULE__{bird: bird})
    |> update_resource(:recording)
    |> update_resource(:image)
  end

  defguard is_resource_key(key) when key in [:recording, :image]

  def update_resource(%Assign{} = assigns, resource_key) when is_resource_key(resource_key) do
    update_resource(assigns, assigns.current.bird, resource_key)
  end

  def update_resource(%Assign{} = assigns, %Bird{} = bird, resource_key)
      when is_resource_key(resource_key) do
    plural = :"#{resource_key}s"

    worker = get_worker(assigns, plural)

    resource =
      case apply(worker.module, :get, [bird, worker]) do
        {:ok, saved_response} ->
          saved_response
          |> Map.fetch!(plural)
          |> Enum.random()
      end

    Map.update!(
      assigns,
      :current,
      &Map.replace!(&1, resource_key, resource)
    )
  end

  defp get_worker(%Assign{services: services}, key) do
    services
    |> Map.fetch!(key)
    |> Map.fetch!(get_worker_key(key))
  end

  defp get_worker_key(:images), do: :PhotoSearch
  defp get_worker_key(:recordings), do: :Recordings
end
