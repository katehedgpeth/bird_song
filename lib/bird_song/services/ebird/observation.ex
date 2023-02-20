defmodule BirdSong.Services.Ebird.Observation do
  @derive Jason.Encoder

  @used_keys [
    "comName",
    "locationPrivate",
    "locName",
    "obsDt",
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
    "sciName",
    "subId"
  ]

  defstruct [
    :com_name,
    :location_private,
    :loc_name,
    :obs_dt,
    :species_code
  ]

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
