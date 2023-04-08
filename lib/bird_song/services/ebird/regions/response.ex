defmodule BirdSong.Services.Ebird.Regions.Region do
  defstruct [:code, :name, :level, :country]

  @type level() :: :country | :subnational1 | :subnational2

  @type t() :: %__MODULE__{
          code: String.t(),
          name: String.t(),
          level: level(),
          country: String.t()
        }
end

defmodule BirdSong.Services.Ebird.Regions.Response do
  alias BirdSong.Services.Ebird.Regions.Region

  defstruct [:level, :country, regions: []]

  @type t() :: %__MODULE__{
          country: String.t(),
          level: Region.level(),
          regions: [Region.t()]
        }

  def parse(raw, {:regions, level: level, country: country}) when is_list(raw),
    do: %__MODULE__{
      level: level,
      country: country,
      regions: Enum.map(raw, &parse_region(&1, level: level, country: country))
    }

  defp parse_region(%{"code" => code, "name" => name}, level: level, country: country) do
    %Region{code: code, name: name, country: country, level: level}
  end
end
