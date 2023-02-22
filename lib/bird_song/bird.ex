defmodule BirdSong.Bird do
  alias BirdSong.Services.XenoCanto.Recording
  alias BirdSong.Services.Ebird.Observation
  alias BirdSong.Services.XenoCanto.Response

  defstruct ebird_code: "", common_name: "", sci_name: "", observations: [], recordings: []

  @type t() :: %__MODULE__{
          ebird_code: String.t(),
          common_name: String.t(),
          observations: [Observation.t()],
          recordings: [Recording],
          sci_name: String.t()
        }

  def new(%Observation{com_name: common_name, sci_name: sci_name, species_code: ebird_code} = obs) do
    %__MODULE__{
      common_name: common_name,
      sci_name: sci_name,
      ebird_code: ebird_code
    }
    |> add_observation(obs)
  end

  def new(%Response{recordings: [recording | _]} = resp) do
    %Recording{
      en: common_name,
      gen: genus,
      sp: species,
      ssp: subspecies
    } = recording

    %__MODULE__{
      common_name: common_name,
      sci_name:
        [genus, species, subspecies]
        |> Enum.join(" ")
        |> String.trim()
    }
    |> add_recordings(resp)
  end

  @spec add_observation(t(), Observation.t()) :: t()
  def add_observation(%__MODULE__{} = bird, %Observation{
        loc_name: loc_name,
        location_private: location_private,
        obs_dt: obs_dt
      }) do
    # no need to keep the name data on each observation record
    min_observation = %Observation{
      loc_name: loc_name,
      location_private: location_private,
      obs_dt: obs_dt
    }

    Map.update!(bird, :observations, &[min_observation | &1])
  end

  def add_recordings(%__MODULE__{} = bird, %Response{recordings: recordings}) do
    Map.update!(bird, :recordings, &Enum.concat([recordings, &1]))
  end
end
