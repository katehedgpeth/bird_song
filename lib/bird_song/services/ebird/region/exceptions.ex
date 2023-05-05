defmodule BirdSong.Services.Ebird.Region.MalformedRegionCodeError do
  defexception [:code]

  @type t() :: %__MODULE__{
          code: String.t()
        }

  def message(%__MODULE__{code: code}) do
    """
    Malformed region code: #{code}

    Expected region code to be in one of these forms:
      country -> XX
      subnational1 -> XX-XX or XX-XXX
      subnational2 -> XX-XX-XXX or XX-XXX-XXX
    """
  end
end

defmodule BirdSong.Services.Ebird.Region.NotFoundError do
  use BirdSong.CustomError, [:code]

  @type t() :: %__MODULE__{
          code: String.t()
        }

  def message_text(%__MODULE__{code: "" <> code}) do
    "Code not found in ETS table: " <> code
  end
end
