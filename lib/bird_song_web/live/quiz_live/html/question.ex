defmodule BirdSongWeb.QuizLive.HTML.Question do
  use Phoenix.LiveComponent
  alias Phoenix.HTML

  alias BirdSongWeb.{
    Components.ButtonGroup,
    Components.GroupButton,
    QuizLive
  }

  alias BirdSong.{
    Bird,
    Quiz,
    Services.Flickr,
    Services.MacaulayLibrary
  }

  def render(%{current: %{bird: nil}} = assigns), do: loading(assigns)

  def render(assigns) do
    ~H"""
    <%= QuizLive.HTML.page_title("What bird do you hear?") %>
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
      <%= QuizLive.HTML.Filters.render(assigns) %>
    </div>
    """
  end

  ####################################################
  ####################################################
  ##
  ##  PRIVATE METHODS
  ##
  ####################################################

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

  defp loading(assigns) do
    ~H"""
    <h2>Loading...</h2>
    """
  end

  defp play_audio(%{current: %{recording: recording}, asset_cdn: asset_cdn}) do
    HTML.Tag.content_tag(:audio, [],
      autoplay: true,
      src: rendering_module(recording).audio_src(recording, asset_cdn)
    )
  end

  defp possible_bird_buttons(birds) do
    birds
    |> Enum.sort_by(& &1.common_name)
    |> Enum.map(&possible_bird_button/1)
    |> ButtonGroup.render()
  end

  defp possible_bird_button(%Bird{common_name: name, species_code: code}) do
    %GroupButton{text: name, value: code, phx_click: ""}
  end

  defp rendering_module(%MacaulayLibrary.Recording{}), do: QuizLive.HTML.Recordings.Ebird
  defp rendering_module(%Flickr.Photo{}), do: QuizLive.HTML.Images.Flickr

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

  defp show_image(assigns) do
    ~H"""
    <div class="flex-none">
      <%= image(assigns) %>
      <%= image_button(assigns) %>
    </div>
    """
  end

  defp show_possible_birds(%{quiz: %Quiz{birds: [%Bird{} | _] = birds}}) do
    HTML.Tag.content_tag(:div, [
      HTML.Tag.content_tag(:h3, "Possible Birds:"),
      possible_bird_buttons(birds)
    ])
  end

  defp show_possible_birds(%{}) do
    {:safe, ""}
  end

  defp show_recording_details(%{
         show_recording_details?: true,
         current: %{recording: %{} = recording},
         asset_cdn: "" <> asset_cdn
       }) do
    rendering_module = rendering_module(recording)

    HTML.Tag.content_tag(:div, [
      rendering_module.attribution(recording),
      rendering_module.recording_type(recording),
      rendering_module.sonogram(recording, asset_cdn)
    ])
  end

  defp show_recording_details(assigns) do
    ~H"""
    <button phx-click="show_recording_details" class="btn btn-outline">Show Recording Details</button>
    """
  end
end
