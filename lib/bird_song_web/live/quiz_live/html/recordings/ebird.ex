defmodule BirdSongWeb.QuizLive.HTML.Recordings.Ebird do
  alias Phoenix.HTML
  alias BirdSong.Services.Ebird.Recordings.Recording

  @behaviour BirdSongWeb.QuizLive.HTML.Recording

  @asset_types %{
    audio: "audio",
    spectrogram: "spectrogram_small"
  }

  def audio_src(%Recording{asset_id: asset_id}, "" <> asset_cdn),
    do: asset_src(asset_id, :audio, asset_cdn)

  def sonogram(%Recording{asset_id: asset_id}, "" <> asset_cdn),
    do:
      asset_id
      |> asset_src(:spectrogram, asset_cdn)
      |> HTML.Tag.img_tag()

  def recording_type(%Recording{}), do: ""

  def also_audible(_recording) do
    {:safe, ""}
  end

  defp asset_src(asset_id, type, "" <> asset_cdn) do
    Path.join([
      asset_cdn,
      "api",
      "v1",
      "asset",
      to_string(asset_id),
      Map.fetch!(@asset_types, type)
    ])
  end
end
