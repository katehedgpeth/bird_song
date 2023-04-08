defmodule BirdSongWeb.QuizLive.HTML.Recording do
  alias BirdSong.Services.{Ebird, XenoCanto}

  @type recording() ::
          Ebird.Recording.t() | XenoCanto.Recording.t()

  @type img_tag() :: Phoenix.HTML.safe()
  @type span_tag() :: Phoenix.HTML.safe()

  @callback sonogram(recording(), String.t()) :: img_tag()
  @callback audio_src(recording(), String.t()) :: String.t()
  @callback also_audible(recording()) :: span_tag()
end
