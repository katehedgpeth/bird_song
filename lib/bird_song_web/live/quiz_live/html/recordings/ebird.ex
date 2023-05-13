defmodule BirdSongWeb.QuizLive.HTML.Recordings.Ebird do
  use Phoenix.LiveComponent
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
    assigns = Map.update!(assigns, :recording, &Map.from_struct/1)

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

  defp contributor_name(%{user_display_name: _} = assigns) do
    ~H"""
      <div>
        <span class="font-bold">Contributed by:</span>
        <%= @user_display_name %>
      </div>

    """
  end

  defp country(%{location: %{"countryName" => country_name}}), do: country_name

  defp subnational1(%{location: %{"subnational1Name" => subnational1}}),
    do: subnational1 <> ", "

  defp subnational2(%{location: %{"subnational2Name" => nil}}), do: ""

  defp subnational2(%{location: %{"subnational2Name" => "" <> subnational2}}),
    do: subnational2 <> ", "

  defp link_to_recording(%{asset_id: asset_id} = assigns) do
    assigns =
      Map.put(assigns, :href, Path.join("https://macaulaylibrary.org/asset", to_string(asset_id)))

    ~H"""
      <div>
        <a href={@href} class="link link-primary block text-xs" target="_blank">
          View on Cornell's Macaulay Library website
        </a>
      </div>
    """
  end

  defp recording_date(%{obs_dt: obs_dt}) do
    {:ok, obs_dt} = NaiveDateTime.from_iso8601(obs_dt)

    assigns = %{
      date:
        obs_dt
        |> NaiveDateTime.to_date()
        |> Calendar.strftime("%B %d, %Y")
    }

    ~H"""
      <div>
        <span class="font-bold">Date: </span>
        <%= @date %>
      </div>
    """
  end

  defp recording_location(%{} = assigns) do
    ~H"""
      <div>
        <span class="font-bold">Location: </span>
        <%= subnational2(assigns) %> <%= subnational1(assigns) %> <%= country(assigns) %>
      </div>
    """
  end
end
