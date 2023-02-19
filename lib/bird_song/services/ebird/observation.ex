defmodule BirdSong.Services.Ebird.Observation do
  @raw_keys [
    "comName",
    "exoticCategory",
    "howMany",
    "lat",
    "lng",
    "locationPrivate",
    "locId",
    "locName",
    "obsDt",
    "obsValid",
    "obsReviewed",
    "sciName",
    "speciesCode",
    "subId"
  ]
  defstruct [
    :com_name,
    :exotic_category,
    :how_many,
    :lat,
    :lng,
    :location_private,
    :loc_name,
    :loc_id,
    :obs_dt,
    :obs_valid,
    :obs_reviewed,
    :sci_name,
    :species_code,
    :sub_id
  ]

  def parse(data) do
    data
    |> Enum.map(&to_snakecase/1)
    |> __struct__()
  end

  defp to_snakecase({key, val}) when key in @raw_keys do
    {key |> Macro.underscore() |> String.to_atom(), val}
  end
end
