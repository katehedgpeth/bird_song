defmodule BirdSongWeb.QuizLive.HTML.Recordings.Ebird do
  use Phoenix.LiveComponent
  alias Phoenix.HTML
  alias BirdSong.Services.MacaulayLibrary.Recording

  # @behaviour BirdSongWeb.QuizLive.HTML.Recording

  @asset_types %{
    audio: "audio",
    spectrogram: "spectrogram_small"
  }

  def audio_src(%Recording{asset_id: asset_id}, asset_cdn) do
    asset_src(asset_id, :audio, asset_cdn)
  end

  def render(%{id: "also_audible"} = assigns) do
    ~H"""
    <span></span>
    """
  end

  def render(%{recording: %Recording{}, id: "recording_details"} = assigns) do
    ~H"""
    <div>
      <.contributor_name {@recording} />
      <.recording_date {@recording} />
      <.recording_location {@recording} />
      <.link_to_recording {@recording} />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <span></span>
    """
  end

  def asset_src(asset_id, type, "" <> asset_cdn) do
    Path.join([
      asset_cdn,
      "api",
      "v1",
      "asset",
      to_string(asset_id),
      Map.fetch!(@asset_types, type)
    ])
  end

  defp contributor_name(%Recording{user_display_name: user_display_name}) do
    HTML.Tag.content_tag(:div, [
      HTML.Tag.content_tag(:span, "Recording contributed by: ", class: "font-bold"),
      user_display_name
    ])
  end

  defp country(%Recording{location: %{"countryName" => country_name}}), do: country_name

  defp subnational1(%Recording{location: %{"subnational1Name" => subnational1}}),
    do: subnational1 <> ", "

  defp subnational2(%Recording{location: %{"subnational2Name" => nil}}), do: ""

  defp subnational2(%Recording{location: %{"subnational2Name" => "" <> subnational2}}),
    do: subnational2 <> ", "

  defp link_to_recording(%Recording{asset_id: asset_id}) do
    HTML.Tag.content_tag(:div, [
      HTML.Link.link("View on Cornell's Macaulay Library website",
        class: "link link-primary block text-xs",
        to: Path.join("https://macaulaylibrary.org/asset", to_string(asset_id)),
        target: "_blank"
      )
    ])
  end

  defp recording_date(%Recording{obs_dt: obs_dt}) do
    {:ok, obs_dt} = NaiveDateTime.from_iso8601(obs_dt)

    HTML.Tag.content_tag(:div, [
      HTML.Tag.content_tag(:span, "Recorded on: ", class: "font-bold"),
      obs_dt
      |> NaiveDateTime.to_date()
      |> Calendar.strftime("%B %d, %Y")
    ])
  end

  defp recording_location(%Recording{} = recording) do
    HTML.Tag.content_tag(
      :div,
      [
        HTML.Tag.content_tag(:span, "Recording Location: ", class: "font-bold"),
        subnational2(recording),
        subnational1(recording),
        country(recording)
      ]
    )
  end
end
