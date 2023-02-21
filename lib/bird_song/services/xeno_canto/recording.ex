defmodule BirdSong.Services.XenoCanto.Recording do
  defstruct [
    # the catalogue number of the recording on xeno-canto
    :id,

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

    # the name of the recordist
    :rec,

    # the country where the recording was made
    :cnt,

    # the name of the locality
    :loc,

    # the latitude of the recording in decimal coordinates
    :lat,

    # the longitude of the recording in decimal coordinates
    :lng,

    # the sound type of the recording (combining both predefined terms such as 'call' or 'song' and additional free text options)
    :type,

    # the sex of the animal
    :sex,

    # the life stage of the animal (adult, juvenile, etc.)
    :stage,

    # the recording method (field recording, in the hand, etc.)
    :method,

    # the URL specifying the details of this recording
    :url,

    # the URL to the audio file
    :file,

    # the original file name of the audio file
    :file_name,

    # an object with the urls to the four versions of sonograms
    :sono,

    # an object with the urls to the three versions of oscillograms
    :osci,

    # the URL describing the license of this recording
    :lic,

    # the current quality rating for the recording
    :q,

    # the length of the recording in minutes
    :length,

    # the time of day that the recording was made
    :time,

    # the date that the recording was made
    :date,

    # the date that the recording was uploaded to xeno-canto
    :uploaded,

    # an array with the identified background species in the recording
    :also,

    # additional remarks by the recordist
    :rmk,

    # sample rate
    :smp
  ]

  @unused_keys [
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
    "alt"
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
    "file-name",
    "sono",
    "osci",
    "lic",
    "q",
    "length",
    "uploaded",
    "also",
    "rmk",
    "playback-used",
    "temp",
    "regnr",
    "auto",
    "dvc",
    "mic",
    "smp"
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
