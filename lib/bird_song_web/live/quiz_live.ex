defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView

  alias Phoenix.LiveView.Socket

  alias __MODULE__.{
    Current,
    EtsTables,
    EventHandlers,
    HTML,
    MessageHandlers
  }

  alias BirdSong.{
    Bird,
    Quiz,
    Services
  }

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  @asset_cdn "https://cdn.download.ams.birds.cornell.edu"
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
    |> assign_new(:services, fn -> Services.ensure_started() end)
    |> assign_new(:asset_cdn, fn -> @asset_cdn end)
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

    HTML.render(assigns)
  end

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
