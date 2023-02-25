defmodule BirdSong.Services.Ebird.Species do
  alias BirdSong.Services.Ebird.Family

  defstruct [
    :common_name,
    :category,
    :family_code,
    :family_common_name,
    :family_sci_name,
    :order,
    :sci_name,
    :species_code
  ]

  @type t :: %__MODULE__{
          common_name: String.t(),
          category: atom,
          family_code: String.t(),
          family_common_name: String.t(),
          family_sci_name: String.t(),
          order: String.t(),
          sci_name: String.t(),
          species_code: String.t()
        }

  @spec parse(Map.t()) :: t()
  def parse(%{
        "bandingCodes" => _banding_code_list,
        "category" => category,
        "comName" => common_name,
        "comNameCodes" => _common_name_code_list,
        "familyCode" => family_code,
        "familyComName" => family_common_name,
        "familySciName" => family_sci_name,
        "order" => order,
        "sciName" => sci_name,
        "sciNameCodes" => _sci_name_code_list,
        "speciesCode" => species_code,
        "taxonOrder" => _taxon_order_int
      })
      when category in [
             "domestic",
             "form",
             "hybrid",
             "intergrade",
             "issf",
             "slash",
             "species",
             "spuh"
           ] do
    %__MODULE__{
      common_name: common_name,
      category: String.to_atom(category),
      family_code: family_code,
      family_common_name: family_common_name,
      family_sci_name: family_sci_name,
      order: order,
      sci_name: sci_name,
      species_code: species_code
    }
  end

  def parse(data) do
    Family.parse(data)
  end
end
