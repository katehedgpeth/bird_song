defmodule BirdSong.Services.Ebird.Observation do
  @derive Jason.Encoder

  @used_keys [
    "comName",
    "locationPrivate",
    "locName",
    "obsDt",
    "sciName",
    "speciesCode"
  ]

  @unused_keys [
    "exoticCategory",
    "howMany",
    "lat",
    "lng",
    "locId",
    "obsValid",
    "obsReviewed",
    "subId"
  ]

  defstruct [
    :com_name,
    :location_private,
    :loc_name,
    :obs_dt,
    :sci_name,
    :species_code
  ]

  @type t() :: %__MODULE__{
          com_name: String.t(),
          location_private: boolean(),
          loc_name: String.t(),
          obs_dt: String.t(),
          sci_name: String.t(),
          species_code: String.t()
        }

  def parse(data) do
    data
    |> Enum.reduce(%{}, &parse_key/2)
    |> __struct__()
  end

  defp parse_key({key, _val}, acc) when key in @unused_keys do
    acc
  end

  defp parse_key({key, val}, acc) when key in @used_keys do
    atom_key = key |> Macro.underscore() |> String.to_atom()
    Map.put(acc, atom_key, val)
  end
end
