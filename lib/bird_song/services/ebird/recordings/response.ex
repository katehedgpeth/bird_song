defmodule BirdSong.Services.Ebird.Recordings.Response do
  alias BirdSong.Services.Ebird.Recordings.Recording

  defstruct recordings: []

  def parse(recordings) when is_list(recordings) do
    %__MODULE__{
      recordings: Enum.map(recordings, &Recording.parse/1)
    }
  end
end
