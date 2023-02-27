defmodule BirdSongWeb.QuizLive.EventHandlers do
  MessageHandlers
  alias Phoenix.LiveView
  alias LiveView.Socket
  alias Ecto.Changeset
  alias BirdSong.Quiz
  alias BirdSongWeb.QuizLive

  def handle_event(
        "start",
        %{"quiz" => changes},
        %Socket{assigns: %{quiz: quiz}} = socket
      ) do
    case Quiz.changeset(quiz, changes) do
      %Changeset{errors: [], data: data} ->
        Process.send(self(), :get_recent_observations, [])
        {:noreply, LiveView.assign(socket, :quiz, data)}

      %Changeset{} = changeset ->
        {:noreply, LiveView.assign(socket, :quiz, changeset)}
    end
  end

  def handle_event("start", %{}, %Socket{} = socket) do
    Process.send(self(), :get_recent_observations, [])

    {:noreply,
     LiveView.assign(
       socket,
       :quiz,
       Quiz.default_changeset() |> Map.fetch!(:data)
     )}
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{assigns: %{quiz: quiz}} = socket) do
    {:noreply, LiveView.assign(socket, :quiz, Quiz.changeset(quiz, changes))}
  end

  def handle_event("validate", %{}, %Socket{} = socket) do
    {:noreply, socket}
  end

  def handle_event("next", _, %Socket{} = socket) do
    {:noreply,
     socket
     |> QuizLive.reset_state()
     |> QuizLive.assign_next_bird()}
  end

  def handle_event(
        "change_recording",
        _,
        %Socket{} = socket
      ) do
    {:noreply, QuizLive.CurrentBird.update_recording(socket)}
  end

  def handle_event("show_answer", _, %Socket{} = socket) do
    {:noreply, LiveView.assign(socket, :show_answer?, true)}
  end

  def handle_event("show_sono", _, %Socket{} = socket) do
    {:noreply, LiveView.assign(socket, :show_sono?, true)}
  end
end
