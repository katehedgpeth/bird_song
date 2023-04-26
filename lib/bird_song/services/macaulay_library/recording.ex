defmodule BirdSong.Services.MacaulayLibrary.Recording do
  defstruct [
    :asset_id,
    :location,
    :media_notes,
    :obs_dt,
    :rating,
    :tags,
    :taxonomy,
    :user_display_name,
    :user_id,
    :user_has_profile,
    :valid?
  ]

  @used_keys [
    "assetId",
    "location",
    "mediaNotes",
    "obsDt",
    "rating",
    "tags",
    "taxonomy",
    "userDisplayName",
    "userId",
    "userHasProfile",
    "valid",
    "valid?"
  ]

  @unused_keys [
    "ageSex",
    "assetState",
    "cursorMark",
    "ebirdChecklistId",
    "exoticCategory",
    "height",
    "licenseId",
    "mediaNotes",
    "mediaType",
    "obsDay",
    "obsDtDisplay",
    "obsMonth",
    "obsTime",
    "obsYear",
    "parentAssetId",
    "ratingCount",
    "restricted",
    "reviewed",
    "source",
    "width"
  ]

  def parse(%{} = raw) do
    raw
    |> Enum.reduce([], &parse_key/2)
    |> __struct__()
  end

  defp parse_key({"valid", val}, acc) do
    parse_key({"valid?", val}, acc)
  end

  defp parse_key({key, val}, acc) when key in @used_keys do
    key =
      key
      |> Macro.underscore()
      |> String.to_existing_atom()

    Keyword.put(acc, key, val)
  end

  defp parse_key({key, _val}, acc) when key in @unused_keys do
    acc
  end
end
