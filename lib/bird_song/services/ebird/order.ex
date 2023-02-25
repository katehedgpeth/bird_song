defmodule BirdSong.Services.Ebird.Order do
  defstruct [
    :common_name,
    :category,
    :sci_name,
    :species_code
  ]

  @type t :: %__MODULE__{
          common_name: String.t(),
          category: atom,
          sci_name: String.t(),
          species_code: String.t()
        }

  def parse(
        %{
          "bandingCodes" => _banding_code_list,
          "category" => category,
          "comName" => common_name,
          "comNameCodes" => _common_name_code_list,
          "sciName" => sci_name,
          "sciNameCodes" => _sci_name_code_list,
          "speciesCode" => species_code,
          "taxonOrder" => _taxon_order
        } = data
      )
      when Kernel.map_size(data) === 8 do
    %__MODULE__{
      common_name: common_name,
      category: category,
      sci_name: sci_name,
      species_code: species_code
    }
  end

  def parse(data) do
    {Kernel.map_size(data), data}
  end
end
