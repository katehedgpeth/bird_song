defmodule BirdSongWeb.QuizLive.HTML.Recording do
  alias BirdSong.Services.{Ebird, XenoCanto}

  @type recording() ::
          Ebird.Recording.t() | XenoCanto.Recording.t()

  @type also_audible() :: String.t()
  @type recording_details() :: String.t()

  @type assigns() :: %{
          id: also_audible() | recording_details(),
          recording: recording()
        }

  @callback render(assigns()) :: Phoenix.LiveView.Rendered.t()
  @callback audio_src(recording(), String.t()) :: String.t()
end
