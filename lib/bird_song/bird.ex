defmodule BirdSong.Bird do
  alias BirdSong.Services.{Ebird, XenoCanto}

  defstruct ebird_code: "",
            common_name: "",
            sci_name: "",
            observations: [],
            recordings: []

  @type t() :: %__MODULE__{
          ebird_code: String.t(),
          common_name: String.t(),
          observations: [Ebird.Observation.t()],
          recordings: [XenoCanto.Recording],
          sci_name: String.t()
        }

  def new(
        %Ebird.Observation{com_name: common_name, sci_name: sci_name, species_code: ebird_code} =
          obs
      ) do
    %__MODULE__{
      common_name: common_name,
      sci_name: sci_name,
      ebird_code: ebird_code
    }
    |> add_observation(obs)
  end

  def new(%XenoCanto.Response{recordings: [recording | _]} = resp) do
    %XenoCanto.Recording{
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

  @spec add_observation(t(), Ebird.Observation.t()) :: t()
  def add_observation(%__MODULE__{} = bird, %Ebird.Observation{
        loc_name: loc_name,
        location_private: location_private,
        obs_dt: obs_dt
      }) do
    # no need to keep the name data on each observation record
    min_observation = %Ebird.Observation{
      loc_name: loc_name,
      location_private: location_private,
      obs_dt: obs_dt
    }

    Map.update!(bird, :observations, &[min_observation | &1])
  end

  def add_recordings(%__MODULE__{} = bird, %XenoCanto.Response{recordings: recordings}) do
    Map.update!(bird, :recordings, &Enum.concat([recordings, &1]))
  end
end
