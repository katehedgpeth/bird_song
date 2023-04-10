defmodule BirdSongWeb.QuizLive.New do
  require Logger
  use Phoenix.LiveView

  alias Phoenix.LiveView.Socket

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.MessageHandlers,
    QuizLive.EventHandlers,
    QuizLive.Assign,
    QuizLive.EtsTables
  }

  alias BirdSong.{
    Quiz,
    Services
  }

  @asset_cdn "https://cdn.download.ams.birds.cornell.edu"

  @text_input_class ~w(
    input
    input-bordered
    w-full
    disabled:text-black/40
    disabled:italic
  )

  def mount(_params, session, socket) do
    {:ok, assign_defaults(socket, session)}
  end

  def render(assigns), do: QuizLive.HTML.render(assigns)

  def assign_defaults(%Socket{} = socket, session) do
    socket
    |> Assign.assign_session_id(session)
    |> assign(:text_input_class, @text_input_class)
    |> assign(:task_timeout, 5_000)
    |> assign(:max_api_tries, 3)
    |> QuizLive.reset_state()
    |> assign_new(:birds, fn -> [] end)
    |> assign_new(:render_listeners, fn -> [] end)
    |> assign_new(:quiz, &Quiz.default_changeset/0)
    |> assign_new(:services, fn -> Services.ensure_started() end)
    |> assign_new(:asset_cdn, fn -> @asset_cdn end)
    |> EtsTables.assign_tables()
  end

  def handle_info(message, socket),
    do: MessageHandlers.handle_info(message, socket)

  def handle_call(message, from, socket),
    do: MessageHandlers.handle_call(message, from, socket)

  def handle_event(message, payload, socket),
    do: EventHandlers.handle_event(message, payload, socket)
end
