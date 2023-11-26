defmodule BirdSong.Services.XenoCanto.Recording do
  alias BirdSong.Bird

  @struct_keys [
    # an array with the identified background species in the recording
    :also,

    # the country where the recording was made
    :cnt,

    # the date that the recording was made
    :date,

    # the English name of the species
    :en,

    # the URL to the audio file
    :file,

    # the generic name of the species
    :gen,

    # the name of the locality
    :loc,

    # the latitude of the recording in decimal coordinates
    :lat,

    # the longitude of the recording in decimal coordinates
    :lng,

    # an object with the urls to the three versions of oscillograms
    :osci,

    # the name of the recordist
    :rec,

    # the sex of the animal
    :sex,

    # an object with the urls to the four versions of sonograms
    :sono,

    # the specific name (epithet) of the species
    :sp,

    # the subspecies name (subspecific epithet)
    :ssp,

    # the life stage of the animal (adult, juvenile, etc.)
    :stage,

    # the sound type of the recording (combining both predefined terms such as 'call' or 'song' and additional free text options)
    :type
  ]

  defstruct @struct_keys

  @unused_atoms [
    # ??? - not in documentation
    :alt,

    # was the recorded animal seen?
    :animal_seen,

    # automatic (non-supervised) recording?
    :auto,

    # despite the field name (which was kept to ensure backwards compatibility),
    # this field indicates whether the recorded animal was seen
    :bird_seen,

    # recording device used
    :dvc,

    # the original file name of the audio file
    :file_name,

    # the group to which the species belongs (birds, grasshoppers)
    :group,

    # the catalogue number of the recording on xeno-canto
    :id,

    # the recording method (field recording, in the hand, etc.)
    :method,

    # microphone used
    :mic,

    # the length of the recording in minutes
    :length,

    # the URL describing the license of this recording
    :lic,

    # was playback used to lure the animal?
    :playback_used,

    # the current quality rating for the recording
    :q,

    # registration number of specimen (when collected)
    :regnr,

    # additional remarks by the recordist
    :rmk,

    # sample rate
    :smp,

    # temperature during recording (applicable to specific groups only)
    :temp,

    # the time of day that the recording was made
    :time,

    # the date that the recording was uploaded to xeno-canto
    :uploaded,

    # the URL specifying the details of this recording
    :url
  ]

  @unused_keys @unused_atoms
               |> Enum.map(&Atom.to_string/1)
               |> Enum.map(&String.replace(&1, "_", "-"))

  @used_keys @struct_keys
             |> Enum.map(&Atom.to_string/1)
             |> Enum.map(&String.replace(&1, "_", "-"))

  @after_compile __MODULE__

  def __after_compile__(_env, _) do
    used = MapSet.new(@used_keys)
    unused = @unused_keys |> Enum.map(&atom_key/1) |> MapSet.new()
    intersection = MapSet.intersection(used, unused)

    if MapSet.size(intersection) !== 0 do
      raise RuntimeError.exception("""
            Expected used and unused keys to be unique sets, but they share these keys:

            #{inspect(intersection)}
            """)
    end
  end

  def parse(data) do
    data
    |> Enum.reduce(%{}, &parse_key/2)
    |> __struct__()
  end

  ####################################
  ####################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################

  defp parse_key({"also", val}, acc) do
    Map.put(acc, :also, Enum.map(val, &use_common_name/1))
  end

  defp parse_key({key, _val}, acc) when key in @unused_keys do
    acc
  end

  defp parse_key({key, val}, acc) when key in @used_keys do
    Map.put(acc, atom_key(key), val)
  end

  defp parse_key({key, _val}, _acc) do
    raise RuntimeError.exception("Unknown Recording key: #{key}")
  end

  defp atom_key(key) when is_binary(key) do
    key
    |> String.replace("-", "_")
    |> String.to_existing_atom()
  end

  defp use_common_name("" <> sci_name) do
    case Bird.get_by_sci_name(sci_name) do
      {:ok, %Bird{common_name: common_name}} ->
        common_name

      {:error, {:not_found, ^sci_name}} ->
        sci_name
    end
  end
end
