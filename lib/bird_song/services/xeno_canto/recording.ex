defmodule BirdSong.Services.XenoCanto.Recording do
  defstruct [
    # the generic name of the species
    :gen,

    # the specific name (epithet) of the species
    :sp,

    # the subspecies name (subspecific epithet)
    :ssp,

    # the group to which the species belongs (birds, grasshoppers)
    :group,

    # the English name of the species
    :en,

    # the URL to the audio file
    :file,

    # an array with the identified background species in the recording
    :also,

    # an object with the urls to the four versions of sonograms
    :sono,

    # an object with the urls to the three versions of oscillograms
    :osci
  ]

  @unused_keys [
    # additional remarks by the recordist
    # :rmk,
    "rmk",

    # sample rate
    # :smp
    "smp",

    # the catalogue number of the recording on xeno-canto
    # :id,
    "id",

    # the name of the recordist
    # :rec,
    "rec",

    # the country where the recording was made
    # :cnt,
    "cnt",

    # the name of the locality
    # :loc,
    "loc",

    # the latitude of the recording in decimal coordinates
    # :lat,
    "lat",

    # the longitude of the recording in decimal coordinates
    # :lng,
    "lng",

    # the sound type of the recording (combining both predefined terms such as 'call' or 'song' and additional free text options)
    # :type,
    "type",

    # the sex of the animal
    # :sex,
    "sex",

    # the life stage of the animal (adult, juvenile, etc.)
    # :stage,
    "stage",

    # the recording method (field recording, in the hand, etc.)
    # :method,
    "method",

    # the URL specifying the details of this recording
    # :url,
    "url",

    # the time of day that the recording was made
    "time",

    # the date that the recording was made
    "date",

    # the date that the recording was uploaded to xeno-canto
    "uploaded",

    # registration number of specimen (when collected)
    "regnr",

    # despite the field name (which was kept to ensure backwards compatibility), this field indicates whether the recorded animal was seen
    "bird-seen",

    # was the recorded animal seen?
    "animal-seen",

    # was playback used to lure the animal?
    "playback-used",

    # automatic (non-supervised) recording?
    "auto",

    # recording device used
    "dvc",

    # microphone used
    "mic",

    # temperature during recording (applicable to specific groups only)
    "temp",

    # ??? - not in documentation
    "alt",

    # the original file name of the audio file
    # :file_name,
    "file-name",

    # the URL describing the license of this recording
    # :lic,
    "lic",

    # the current quality rating for the recording
    # :q,
    "q",

    # the length of the recording in minutes
    # :length,
    "length",

    # the time of day that the recording was made
    # :time,
    "time",

    # the date that the recording was made
    # :date,
    "date",

    # the date that the recording was uploaded to xeno-canto
    # :uploaded,
    "uploaded"
  ]

  @used_keys [
    "id",
    "gen",
    "sp",
    "ssp",
    "group",
    "en",
    "rec",
    "cnt",
    "loc",
    "lat",
    "lng",
    "type",
    "sex",
    "stage",
    "method",
    "url",
    "file",
    "also",
    "rmk",
    "playback-used",
    "temp",
    "regnr",
    "auto",
    "dvc",
    "mic",
    "smp",
    "sono",
    "osci"
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
    atom_key = key |> String.replace("-", "_") |> String.to_atom()
    Map.put(acc, atom_key, val)
  end
end
