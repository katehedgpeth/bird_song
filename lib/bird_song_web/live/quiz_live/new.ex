defmodule BirdSongWeb.QuizLive.New do
  require Logger
  use Phoenix.LiveView

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.MessageHandlers,
    QuizLive.EventHandlers,
    QuizLive.Assign
  }

  on_mount BirdSongWeb.QuizLive.User
  on_mount {BirdSong.PubSub, :subscribe}
  on_mount {Assign, :assign_services}

  def render(assigns) do
    assigns
    |> Map.put(:inner_template, QuizLive.HTML.NewQuiz)
    |> QuizLive.HTML.render()
  end

  defdelegate handle_info(message, socket), to: MessageHandlers
  defdelegate handle_event(message, payload, socket), to: EventHandlers

  if Mix.env() === :test do
    defdelegate handle_call(message, payload, socket), to: MessageHandlers
  end
end
