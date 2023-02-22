defmodule BirdSong.Services.XenoCanto.Response do
  alias BirdSong.Services.XenoCanto.Recording

  @used_keys ["numRecordings", "numSpecies", "page", "numPages", "recordings"]

  defstruct [:num_recordings, :num_species, :page, :num_pages, :recordings]

  @type t() :: %__MODULE__{
          num_recordings: integer(),
          num_species: integer(),
          page: integer(),
          num_pages: integer(),
          recordings: [Recording.t()]
        }

  def parse(data) do
    data
    |> Enum.reduce(%{}, &parse_key/2)
    |> __struct__()
  end

  defp parse_key({"recordings", recordings}, acc) do
    Map.put(acc, :recordings, Enum.map(recordings, &Recording.parse/1))
  end

  defp parse_key({key, val}, acc) when key in @used_keys do
    atom_key = key |> Macro.underscore() |> String.to_atom()
    Map.put(acc, atom_key, val)
  end
end
