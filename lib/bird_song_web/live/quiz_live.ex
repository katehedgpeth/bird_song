defmodule BirdSongWeb.QuizLive do
  require Logger

  use Phoenix.LiveView

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias BirdSong.{
    Accounts,
    Quiz
  }

  alias BirdSongWeb.Components.Stats

  alias __MODULE__.{
    Assign,
    Current,
    EventHandlers,
    HTML,
    MessageHandlers,
    Visibility
  }

  on_mount BirdSongWeb.QuizLive.User
  on_mount {BirdSong.PubSub, :subscribe}
  on_mount {Assign, :assign_services}
  on_mount {Stats, :get}

  @impl LiveView
  def mount(_params, _session, %Socket{} = socket) do
    {:ok,
     socket.assigns.user.id
     |> Quiz.get_current_for_user!()
     |> case do
       nil ->
         LiveView.push_redirect(socket, to: "/quiz/new")

       %Quiz{} = quiz ->
         socket.assigns
         |> Assign.assigns_to_struct()
         |> reset_state()
         |> Map.replace!(:quiz, quiz)
         |> Current.assign_current()
         |> Assign.assign(socket)
     end}
  end

  @impl LiveView
  defdelegate handle_info(message, socket), to: MessageHandlers

  @impl LiveView
  defdelegate handle_event(message, payload, socket), to: EventHandlers

  if Mix.env() === :test do
    @impl LiveView
    defdelegate handle_call(message, payload, socket), to: MessageHandlers
  end

  @impl LiveView
  def render(assigns) do
    assigns
    |> Map.put(:inner_template, HTML.Question)
    |> HTML.render()
  end

  def assign_next_bird(
        %Assign{
          current: %Current{bird: nil},
          quiz: %Quiz{}
        } = assigns
      ) do
    Current.assign_current(assigns)
  end

  def assign_next_bird(%Socket{} = socket) do
    socket
  end

  def reset_state(%Assign{} = assigns) do
    assigns
    |> Current.reset()
    |> Map.put(:visibility, %Visibility{})
  end
end
