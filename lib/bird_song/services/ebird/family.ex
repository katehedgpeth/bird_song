defmodule BirdSong.Services.Ebird.Family do
  alias BirdSong.Services.Ebird.Order

  defstruct [
    :common_name,
    :category,
    :order,
    :sci_name,
    :species_code
  ]

  @type t :: %__MODULE__{
          common_name: String.t(),
          category: atom,
          order: String.t(),
          sci_name: String.t(),
          species_code: String.t()
        }

  def parse(
        %{
          "bandingCodes" => _banding_code_list,
          "comName" => common_name,
          "comNameCodes" => _common_name_code_list,
          "category" => category,
          "order" => order,
          "sciName" => sci_name,
          "sciNameCodes" => _sci_name_code_list,
          "speciesCode" => species_code,
          "taxonOrder" => _taxon_order
        } = data
      )
      when Kernel.map_size(data) === 9 do
    %__MODULE__{
      common_name: common_name,
      category: category,
      order: order,
      sci_name: sci_name,
      species_code: species_code
    }
  end

  def parse(data) do
    Order.parse(data)
  end
end
