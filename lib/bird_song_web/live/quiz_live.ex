defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView

  alias Phoenix.{LiveView, LiveView.Socket}

  alias __MODULE__.{
    Assign,
    Current,
    EtsTables,
    EventHandlers,
    HTML,
    MessageHandlers
  }

  alias BirdSong.Bird

  def mount(params, session, socket) do
    socket =
      socket
      |> Assign.assign_session_id(session)
      |> EtsTables.assign_tables(EtsTables.get_ets_server_name(params))
      |> EtsTables.Assigns.lookup_session()
      |> case do
        {:ok, %{} = assigns} ->
          %{socket | assigns: assigns}
          |> assign_next_bird()

        {:error, {:not_found, _}} ->
          LiveView.push_redirect(socket, to: "/quiz/new")
      end

    {:ok, socket}
  end

  def handle_info(message, socket),
    do: MessageHandlers.handle_info(message, socket)

  def handle_event(message, payload, socket),
    do: EventHandlers.handle_event(message, payload, socket)

  def render(assigns) do
    Enum.each(assigns[:render_listeners], &send(&1, {:render, assigns}))

    assigns
    |> Map.put(:inner_template, &HTML.Question.render/1)
    |> HTML.render()
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
