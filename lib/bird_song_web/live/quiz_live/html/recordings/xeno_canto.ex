defmodule BirdSongWeb.QuizLive.HTML.Recordings.XenoCanto do
  use Phoenix.LiveComponent
  alias Phoenix.HTML
  alias BirdSong.Services.XenoCanto

  def render(%{id: "recording_details", recording: %XenoCanto.Recording{}} = assigns) do
    ~H"""
      <div class="badge badge-neutral mb-2">
        Sound type: <%= @recording.type %>
      </div>

      <div>
        <%= HTML.Tag.img_tag(@recording.sono["large"]) %>
      </div>
    """
  end

  def render(%{id: "also_audible", recording: %XenoCanto.Recording{}} = assigns) do
    ~H"""
    <div class="text-black/40 italic">
      Also audible:
      <%= for also <- @recording.also do %>
        <div><%= also %></div>
      <% end %>

    </div>
    """
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
