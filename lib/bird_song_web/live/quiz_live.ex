defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView
  use Phoenix.HTML

  alias Phoenix.HTML
  alias Phoenix.LiveView.Socket
  alias Ecto.Changeset

  alias __MODULE__.{
    Current,
    EtsTables,
    MessageHandlers,
    EventHandlers
  }

  alias BirdSong.{
    Bird,
    Services,
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
    {:ok, assign_defaults(socket)}
  end

  def assign_defaults(%Socket{} = socket) do
    socket
    |> assign(:text_input_class, @text_input_class)
    |> assign(:task_timeout, 5_000)
    |> assign(:max_api_tries, 3)
    |> reset_state()
    |> assign_new(:birds, fn -> [] end)
    |> assign_new(:render_listeners, fn -> [] end)
    |> assign_new(:quiz, &Quiz.default_changeset/0)
    |> assign_new(:services, fn -> %Services{} end)
    |> EtsTables.assign_new_tables()
  end

  def handle_info(message, socket),
    do: MessageHandlers.handle_info(message, socket)

  def handle_call(message, from, socket),
    do: MessageHandlers.handle_call(message, from, socket)

  def handle_event(message, payload, socket),
    do: EventHandlers.handle_event(message, payload, socket)

  def render(assigns) do
    Enum.each(assigns[:render_listeners], &send(&1, {:render, assigns}))

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
      <%= HTML.Tag.content_tag :audio, [], autoplay: true, src: get_recording_source(@current) %>
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
         current: %{bird: %Bird{common_name: name}}
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

  defp show_recording_details(%{
         show_recording_details?: true,
         current: %{recording: %Recording{} = recording}
       }) do
    HTML.Tag.content_tag(:div, [
      recording_type(recording),
      recording_sono(recording)
    ])
  end

  defp show_recording_details(assigns) do
    ~H"""
    <button phx-click="show_recording_details" class="btn btn-outline">Show Recording Details</button>
    """
  end

  defp get_recording_source(%{recording: %Recording{file: file}}), do: file

  defp image(%{show_image?: true, current: %{image: %Flickr.Photo{url: url}}}) do
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

  defp recording_sono(%Recording{sono: %{"large" => large_sono}}),
    do: HTML.Tag.img_tag(large_sono)

  defp recording_type(%Recording{type: type}),
    do: HTML.Tag.content_tag(:div, ["Sound type: ", type], class: "badge badge-neutral mb-2")

  def assign_next_bird(
        %Socket{
          assigns: %{
            current: %Current{bird: nil},
            birds: [%Bird{} | _]
          }
        } = socket
      ) do
    Current.assign_current(socket)
  end

  def assign_next_bird(%Socket{} = socket) do
    socket
  end

  def reset_state(%Socket{} = socket) do
    socket
    |> Current.reset()
    |> assign(:show_answer?, false)
    |> assign(:show_recording_details?, false)
    |> assign(:show_image?, false)
  end
end
