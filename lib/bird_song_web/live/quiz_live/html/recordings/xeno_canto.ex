defmodule BirdSongWeb.QuizLive.HTML.Recordings.XenoCanto do
  @behaviour BirdSongWeb.QuizLive.HTML.Recording
  alias Phoenix.HTML
  alias BirdSong.Services.XenoCanto

  def also_audible(%XenoCanto.Recording{also: also}) do
    HTML.Tag.content_tag(
      :div,
      ["Also audible: ", Enum.map(also, &HTML.Tag.content_tag(:div, [&1]))],
      class: "text-black/40 italic"
    )
  end

  def attribution(%XenoCanto.Recording{}) do
    {:safe, ""}
  end

  def audio_src(%XenoCanto.Recording{file: file}, _), do: file

  def sonogram(%XenoCanto.Recording{sono: %{"large" => large_sono}}, _),
    do: HTML.Tag.img_tag(large_sono)

  def recording_type(%XenoCanto.Recording{type: type}),
    do: HTML.Tag.content_tag(:div, ["Sound type: ", type], class: "badge badge-neutral mb-2")
end
