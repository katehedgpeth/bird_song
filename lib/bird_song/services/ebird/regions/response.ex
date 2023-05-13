defmodule BirdSong.Services.Ebird.Regions.Response do
  alias BirdSong.Services.Ebird.Region

  defstruct [:level, :country, regions: []]

  @type t() :: %__MODULE__{
          country: String.t(),
          level: Region.level(),
          regions: [Region.t()]
        }

  def parse(raw, {:regions, level: level, parent: country}) when is_list(raw) do
    %__MODULE__{
      level: level,
      country: country,
      regions: Enum.map(raw, &Region.parse!/1)
    }
  end
end
