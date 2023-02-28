defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView
  use Phoenix.HTML

  alias Phoenix.HTML
  alias Phoenix.LiveView.Socket
  alias Ecto.Changeset

  alias __MODULE__.{
    CurrentBird,
    Caches,
    EtsTables,
    MessageHandlers,
    EventHandlers
  }

  alias BirdSong.{
    Bird,
    Services.Flickr,
    Services.XenoCanto,
    Quiz
  }

  alias XenoCanto.Recording

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:text_input_class, @text_input_class)
     |> reset_state()
     |> assign_new(:render_listeners, fn -> [] end)
     |> assign_new(:quiz, &Quiz.default_changeset/0)
     |> EtsTables.assign_new()
     |> Caches.assign_new()
     |> EtsTables.Birds.update_bird_count()}
  end

  def handle_info(message, socket),
    do: MessageHandlers.handle_info(message, socket)

  def handle_event(message, payload, socket),
    do: EventHandlers.handle_event(message, payload, socket)

  def render(assigns) do
    Enum.each(assigns[:render_listeners], &send(&1, assigns))

    ~H"""
    <div class="flex items-center flex-col">
      <%= inner_content(assigns) %>
    </div>
    """
  end

  def inner_content(%{quiz: %Changeset{}} = assigns), do: new(assigns)
  def inner_content(%{current_bird: nil} = assigns), do: loading(assigns)

  def inner_content(%{current_bird: %{bird: %Bird{}, recording: %Recording{}}} = assigns),
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
        <%= HTML.Form.text_input q, :region, disabled: true, class: @text_input_class %>
      </div>

      <%= HTML.Form.submit "Let's go!", class: "btn btn-primary block w-full" %>
    </.form>
    """
  end

  def question(assigns) do
    ~H"""
    <%= page_title("What bird do you hear?") %>
    <div class="flex gap-10 flex-col">
      <%= HTML.Tag.content_tag :audio, [], autoplay: true, src: get_recording_source(@current_bird) %>
      <div class="flex justify-center gap-5">
        <button phx-click="change_recording" class="btn btn-outline">Hear a different recording of this bird</button>
        <button phx-click="next" class="btn btn-secondary">Skip to next bird</button>
      </div>
      <div class="bg-slate-100 p-10 w-full">
        <%= show_answer(assigns) %>
      </div>
      <%= show_image(assigns) %>
      <%= show_sono(assigns) %>
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
         current_bird: %{
           bird: %Bird{common_name: name},
           recording: %Recording{also: also},
           image: _
         }
       })
       when length(also) > 0,
       do:
         HTML.Tag.content_tag(
           :div,
           [
             name,
             HTML.Tag.content_tag(
               :div,
               ["Also audible: ", Enum.map(also, &HTML.Tag.content_tag(:div, [&1]))],
               class: "text-black/40 italic"
             )
           ],
           class: "text-center"
         )

  defp show_answer(%{
         show_answer?: true,
         current_bird: %{bird: %Bird{common_name: name}}
       }),
       do: HTML.Tag.content_tag(:div, name, class: "mx-auto text-center")

  defp show_answer(assigns),
    do: ~H"""
    <button phx-click="show_answer" class="btn btn-outline mx-auto block">Show Answer</button>
    """

  defp show_image(assigns) do
    ~H"""
    <%= image(assigns) %>
    <%= image_button(assigns) %>
    """
  end

  defp show_sono(%{
         show_sono?: true,
         current_bird: %{recording: %Recording{sono: %{"large" => large_sono}}}
       }) do
    HTML.Tag.img_tag(large_sono)
  end

  defp show_sono(assigns) do
    ~H"""
    <button phx-click="show_sono" class="btn btn-outline">Show Sonogram</button>
    """
  end

  defp get_recording_source(%{recording: %Recording{file: file}}), do: file

  defp image(%{show_image?: true, current_bird: %{image: %Flickr.Photo{url: url}}}) do
    HTML.Tag.img_tag(url, class: "block")
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

  def assign_next_bird(
        %Socket{
          assigns: %{
            current_bird: nil,
            quiz: %Quiz{birds: [next | rest]} = quiz
          }
        } = socket
      ) do
    socket
    |> CurrentBird.assign_current_bird(next)
    |> assign(:quiz, %{quiz | birds: rest})
  end

  def assign_next_bird(%Socket{} = socket) do
    socket
  end

  def reset_state(%Socket{} = socket) do
    socket
    |> assign(:current_bird, nil)
    |> assign(:show_answer?, false)
    |> assign(:show_sono?, false)
    |> assign(:show_image?, false)
  end
end
