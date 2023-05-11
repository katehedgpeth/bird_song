defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView

  alias BirdSongWeb.QuizLive.Visibility
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

  def mount(_params, session, socket) do
    socket =
      socket
      |> Assign.assign_session_id(session)
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

  defdelegate handle_info(message, socket), to: MessageHandlers

  defdelegate handle_event(message, payload, socket), to: EventHandlers

  if Mix.env() === :test do
    defdelegate handle_call(message, payload, socket), to: MessageHandlers
  end

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
    |> assign(:visibility, %Visibility{})
  end
end
