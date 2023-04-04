defmodule BirdSong.Services.Ebird.RegionCodes.Response do
  defstruct [:region, codes: []]

  @type t() :: %__MODULE__{
          codes: [String.t()],
          region: String.t()
        }

  def parse(codes, {:region_codes, region}) when is_list(codes) do
    %__MODULE__{codes: codes, region: region}
  end
end
