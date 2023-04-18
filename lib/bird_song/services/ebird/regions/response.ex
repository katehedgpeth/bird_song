defmodule BirdSong.Services.Ebird.Regions.Response do
  alias BirdSong.Services.Ebird.Regions.Region

  defstruct [:level, :country, regions: []]

  @type t() :: %__MODULE__{
          country: String.t(),
          level: Region.level(),
          regions: [Region.t()]
        }

  def parse(raw, {:regions, level: level, parent: country}) when is_list(raw),
    do: %__MODULE__{
      level: level,
      country: country,
      regions: Enum.map(raw, &parse_region(&1, level: level))
    }

  defp parse_region(%{"code" => code, "name" => name}, level: level) do
    %Region{code: code, name: name, level: level}
  end
end
