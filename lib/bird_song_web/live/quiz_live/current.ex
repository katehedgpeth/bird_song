defmodule BirdSongWeb.QuizLive.Current do
  require Logger
  use BirdSongWeb.QuizLive.Assign
  alias BirdSong.Services.Flickr.Photo
  alias BirdSong.Services.XenoCanto.Recording
  alias BirdSong.{Bird, Services}

  alias Services.{
    XenoCanto,
    Flickr,
    Service
  }

  defstruct [:bird, :recording, :image]

  @type t() :: %__MODULE__{
          bird: Bird.t(),
          image: Flickr.Photo.t(),
          recording: XenoCanto.Recording.t()
        }

  def reset(%Socket{} = socket) do
    assign(socket, :current, %__MODULE__{})
  end

  def assign_current(
        %Socket{
          assigns: %{
            current: %__MODULE__{bird: nil},
            birds: [%Bird{} = bird | rest]
          }
        } = socket
      ) do
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

      %Socket{} ->
        socket
        |> reset()
        # drop bird with missing data from list,
        # so we don't try to render it again this session
        |> assign(:birds, rest)
        |> assign_current()
    end
  end

  def update_recording(%Socket{} = socket) do
    update_recording(socket, get_current(socket, :bird))
  end

  def update_recording(%Socket{} = socket, %Bird{} = bird) do
    update_resource(socket, bird, :recording)
  end

  def update_image(%Socket{} = socket) do
    update_image(socket, get_current(socket, :bird))
  end

  def update_image(%Socket{} = socket, %Bird{} = bird) do
    update_resource(socket, bird, :image)
  end

  defguard is_resource_key(key) when key in [:recording, :image]

  defp update_resource(%Socket{} = socket, resource_key) when is_resource_key(resource_key) do
    update_resource(socket, get_current(socket, :bird), resource_key)
  end

  defp update_resource(%Socket{} = socket, %Bird{} = bird, resource_key)
       when is_resource_key(resource_key) do
    plural = :"#{resource_key}s"

    %Service{module: module, whereis: whereis} =
      socket
      |> get_assign(:services)
      |> Map.fetch!(plural)

    resource =
      case apply(module, :get, [bird, whereis]) do
        {:ok, saved_response} ->
          saved_response
          |> Map.fetch!(plural)
          |> Enum.random()

        {:error, _} ->
          warn_no_data(bird, plural)
          {:error, :no_data}
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

  defp warn_no_data(%Bird{common_name: common_name}, missing_data) do
    [
      inspect([__MODULE__]),
      "error=missing_data",
      "bird=" <> common_name,
      "missing=#{missing_data}"
    ]
    |> Enum.join(" ")
    |> Logger.warn()
  end
end
