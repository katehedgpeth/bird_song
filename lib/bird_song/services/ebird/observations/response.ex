defmodule BirdSong.Services.Ebird.Observations.Response do
  alias BirdSong.Services.Ebird.Observations.Observation

  defstruct [:region, observations: []]

  @type t() :: %__MODULE__{
          observations: [Observation.t()],
          region: String.t()
        }

  def parse(observations, {:recent_observations, region}) when is_list(observations) do
    %__MODULE__{
      observations: Enum.map(observations, &Observation.parse/1),
      region: region
    }
  end
end
