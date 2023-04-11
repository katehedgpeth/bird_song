defmodule BirdSongWeb.QuizLive.HTML do
  use Phoenix.HTML
  use Phoenix.LiveView

  alias Phoenix.HTML
  alias BirdSong.{Bird, Services.Ebird, Services.Flickr}

  def render(assigns) do
    ~H"""
    &QuizLive.HTML.render/1 should not have been called
    """
  end

  def render(assigns, page) do
    ~H"""
    <div class="flex items-center flex-col">
      <%= apply(__MODULE__, page, [assigns]) %>
    </div>
    """
  end

  defp group_filter_buttons(categories) do
    categories
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&group_filter_button/1)
  end

  defp group_filter_button({group_name, selected?}) do
    HTML.Tag.content_tag(:button, group_name,
      type: :button,
      value: group_name,
      "phx-click": "set_species_category",
      class: "btn btn-xs #{if selected?, do: "", else: "btn-outline"}"
    )
  end

  def new(assigns) do
    ~H"""
    <%= page_title("How well do you know your bird songs?") %>
    <%= filters(assigns) %>
    """
  end

  def question(%{current: %{bird: nil}} = assigns), do: loading(assigns)

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
      <div class="flex space-x-10">
        <%= show_image(assigns) %>
        <%= show_possible_birds(assigns) %>
      </div>
      <%= show_recording_details(assigns) %>
      <%= show_quiz_details(assigns) %>
      <%= filters(assigns) %>
    </div>
    """
  end

  defp filters(assigns) do
    ~H"""
    <.form
      let={q}
      for={@filters}
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
      <div>
        <%= show_group_filter_buttons(assigns) %>
      </div>

      <%= HTML.Form.submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
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

  defp show_group_filter_buttons(%{species_categories: categories}) do
    HTML.Tag.content_tag(:div, [
      HTML.Tag.content_tag(:h3, "Limit to these groups (optional):"),
      HTML.Tag.content_tag(
        :div,
        group_filter_buttons(categories),
        class: "flex flex-wrap space-x-3"
      )
    ])
  end

  defp show_image(assigns) do
    ~H"""
    <div class="flex-none">
      <%= image(assigns) %>
      <%= image_button(assigns) %>
    </div>
    """
  end

  defp show_possible_birds(assigns) do
    HTML.Tag.content_tag(:div, [
      HTML.Tag.content_tag(:h3, "Possible Birds:"),
      HTML.Tag.content_tag(
        :div,
        assigns
        |> Map.fetch!(:quiz)
        |> Map.fetch!(:birds)
        |> Enum.map(&HTML.Tag.content_tag(:div, &1.common_name, class: "btn btn-outline btn-xs")),
        class: "flex flex-wrap space-x-2 space-y-1 justify-start"
      )
    ])
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

  defp show_quiz_details(assigns) do
    ~H"""
    <div>Total possible birds:  <%= length(@birds) %></div>
    <div>Selected birds: <%= length(@quiz.birds) %></div>

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
