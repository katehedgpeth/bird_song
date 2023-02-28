defmodule BirdSong.Bird do
  alias BirdSong.Services.{Ebird, XenoCanto}

  defstruct ebird_code: "",
            common_name: "",
            sci_name: ""

  @type t() :: %__MODULE__{
          ebird_code: String.t(),
          common_name: String.t(),
          sci_name: String.t()
        }

  def new(%Ebird.Observation{
        com_name: common_name,
        sci_name: sci_name,
        species_code: ebird_code
      }) do
    %__MODULE__{
      common_name: common_name,
      sci_name: sci_name,
      ebird_code: ebird_code
    }
  end

  def new(%XenoCanto.Response{
        recordings: [
          %XenoCanto.Recording{
            en: common_name,
            gen: genus,
            sp: species,
            ssp: subspecies
          }
          | _
        ]
      }) do
    %__MODULE__{
      common_name: common_name,
      sci_name:
        [genus, species, subspecies]
        |> Enum.join(" ")
        |> String.trim()
    }
  end
end
