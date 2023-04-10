defmodule BirdSongWeb.QuizLive.HTML do
  use Phoenix.HTML
  use Phoenix.LiveView

  alias Ecto.Changeset
  alias Phoenix.HTML
  alias BirdSong.{Bird, Services.Ebird, Services.Flickr}

  def render(assigns) do
    ~H"""
    <div class="flex items-center flex-col">
      <%= inner_content(assigns) %>
    </div>
    """
  end

  def inner_content(%{quiz: %Changeset{}} = assigns), do: new(assigns)
  def inner_content(%{current: %{bird: nil}} = assigns), do: loading(assigns)

  def inner_content(%{current: %{bird: %Bird{}}} = assigns),
    do: question(assigns)

  def new(assigns) do
    ~H"""
    <%= page_title("How well do you know your bird songs?") %>
    <.form
      let={q}
      for={@quiz}
      id="settings"
      phx-change="validate"
      phx-submit="start"
      class="w-full md:w-1/2 flex flex-col space-y-4"
    >
      <div>
        <%=
          HTML.Form.label q, :region, HTML.Tag.content_tag(:span, [
            "Region",
            HTML.Tag.content_tag(:span, " (can be city, state, or country)", class: "italic")
          ])
        %>
        <div class="flex">
          <%= HTML.Form.text_input q, :region, "phx-debounce": 3, class: @text_input_class %>
          <%= HTML.Tag.content_tag(:button, "Set region", type: :button, "phx-click": "set_region", class: "btn") %>
        </div>
      </div>
      <%= show_group_filter_buttons(assigns) %>

      <%= HTML.Form.submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
    """
  end

  def question(assigns) do
    ~H"""
    <%= page_title("What bird do you hear?") %>
    <div class="flex gap-10 flex-col">
      <%= play_audio(assigns) %>
      <div class="flex justify-center gap-5">
        <button phx-click="change_recording" class="btn btn-outline">Hear a different recording of this bird</button>
        <button phx-click="next" class="btn btn-secondary">Skip to next bird</button>
      </div>
      <div class="bg-slate-100 p-10 w-full">
        <%= show_answer(assigns) %>
      </div>
      <%= show_image(assigns) %>
      <%= show_recording_details(assigns) %>
    </div>
    """
  end

  def loading(assigns) do
    ~H"""
    <h2>Loading...</h2>
    """
  end

  defp page_title("" <> title) do
    HTML.Tag.content_tag(:h1, title, class: "mb-4")
  end

  defp show_answer(%{
         show_answer?: true,
         current: %{
           bird: %Bird{common_name: name},
           recording: recording,
           image: _
         }
       }),
       do:
         HTML.Tag.content_tag(
           :div,
           [
             name,
             rendering_module(recording).also_audible(recording)
           ],
           class: "text-center"
         )

  defp show_answer(%{
         show_answer?: true,
         current: %{bird: %Bird{common_name: name}}
       }),
       do: HTML.Tag.content_tag(:div, name, class: "mx-auto text-center")

  defp show_answer(assigns),
    do: ~H"""
    <button phx-click="show_answer" class="btn btn-outline mx-auto block">Show Answer</button>
    """

  defp show_group_filter_buttons(%{birds: []}) do
    ""
  end

  defp show_group_filter_buttons(%{}) do
    "GROUP FILTER BUTTONS HERE"
  end

  defp show_image(assigns) do
    ~H"""
    <%= image(assigns) %>
    <%= image_button(assigns) %>
    """
  end

  defp show_recording_details(%{
         show_recording_details?: true,
         current: %{recording: %{} = recording},
         asset_cdn: "" <> asset_cdn
       }) do
    HTML.Tag.content_tag(:div, [
      rendering_module(recording).recording_type(recording),
      rendering_module(recording).sonogram(recording, asset_cdn)
    ])
  end

  defp show_recording_details(assigns) do
    ~H"""
    <button phx-click="show_recording_details" class="btn btn-outline">Show Recording Details</button>
    """
  end

  defp play_audio(%{current: %{recording: recording}, asset_cdn: asset_cdn}) do
    HTML.Tag.content_tag(:audio, [],
      autoplay: true,
      src: rendering_module(recording).audio_src(recording, asset_cdn)
    )
  end

  defp rendering_module(%Ebird.Recordings.Recording{}), do: __MODULE__.Recordings.Ebird
  defp rendering_module(%Flickr.Photo{}), do: __MODULE__.Images.Flickr

  defp image(%{show_image?: true, current: %{image: image}}) do
    image
    |> rendering_module()
    |> apply(:src, [image])
    |> HTML.Tag.img_tag(class: "block")
  end

  defp image(%{show_image?: false}) do
    ""
  end

  defp image_button(%{show_image?: show?}) do
    action = if show?, do: "change", else: "show"

    HTML.Tag.content_tag(:button, String.capitalize(action) <> " Image",
      phx: [click: action <> "_image"],
      class: "btn btn-outline block"
    )
  end
end
