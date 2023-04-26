defmodule BirdSong.Services.MacaulayLibrary.Response do
  alias BirdSong.{Bird, Services.MacaulayLibrary.Recording}

  defstruct recordings: []

  def parse(recordings, %Bird{}) when is_list(recordings) do
    %__MODULE__{
      recordings: Enum.map(recordings, &Recording.parse/1)
    }
  end
end
