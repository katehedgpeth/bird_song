defmodule BirdSongWeb.QuizLive.Caches do
  alias Phoenix.LiveView.Socket
  alias BirdSong.Services.XenoCanto
  alias BirdSong.Bird

  defstruct [:xeno_canto]

  @type t() :: %__MODULE__{
          xeno_canto: XenoCanto | pid()
        }

  @spec assign_new(Socket.t()) :: Socket.t()
  def assign_new(%Socket{} = socket) do
    Phoenix.LiveView.assign_new(socket, :caches, &new/0)
  end

  @spec has_all_data?(Socket.t(), Bird.t()) :: boolean()
  def has_all_data?(%Socket{} = socket, %Bird{} = bird) do
    has_recordings?(socket, bird)
  end

  def has_recordings?(%Socket{} = socket, %Bird{} = bird) do
    XenoCanto.has_data?(bird, get_cache(socket, :xeno_canto))
  end

  def get_recordings(%Socket{} = socket, %Bird{} = bird) do
    XenoCanto.get_recordings(bird, get_cache(socket, :xeno_canto))
  end

  @spec new() :: t()
  defp new() do
    %__MODULE__{
      xeno_canto: XenoCanto
    }
  end

  defp get_cache(%Socket{assigns: %{caches: %__MODULE__{xeno_canto: xeno_canto}}}, :xeno_canto),
    do: xeno_canto
end
