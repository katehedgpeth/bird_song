defmodule BirdSongWeb.QuizLive.EventHandlers do
  use BirdSongWeb.QuizLive.Assign
  alias Phoenix.LiveView
  alias BirdSongWeb.QuizLive.EtsTables
  alias Ecto.Changeset
  alias BirdSong.Quiz
  alias BirdSongWeb.{QuizLive, QuizLive.Current}

  def handle_event("set_region", %{"value" => value}, %Socket{} = socket) do
    send(self(), :get_region_species_codes)
    {:noreply, set_region(socket, value)}
  end

  def handle_event(
        "start",
        %{"quiz" => changes},
        %Socket{} = socket
      ) do
    socket
    |> validate_quiz(changes)
    |> case do
      %Quiz{} = quiz ->
        Process.send(self(), :get_region_species_codes, [])

        {:noreply,
         socket
         |> assign(:quiz, quiz)
         |> EtsTables.Assigns.remember_session()
         |> LiveView.push_redirect(to: "/quiz")}

      %Changeset{} = changeset ->
        {:noreply, assign(socket, :quiz, changeset)}
    end
  end

  def handle_event("start", %{}, %Socket{assigns: %{birds: [], quiz: %Quiz{}}} = socket) do
    Process.send(self(), :get_region_species_codes, [])

    {:noreply, socket}
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{} = socket) do
    {:noreply, assign(socket, :quiz, update_quiz(socket, changes))}
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
    {:noreply, Current.update_recording(socket)}
  end

  def handle_event("show_answer", _, %Socket{} = socket) do
    {:noreply,
     socket
     |> assign(:show_image?, true)
     |> assign(:show_answer?, true)}
  end

  def handle_event("show_recording_details", _, %Socket{} = socket) do
    {:noreply, assign(socket, :show_recording_details?, true)}
  end

  def handle_event("show_image", _, %Socket{} = socket) do
    {:noreply, assign(socket, :show_image?, true)}
  end

  def handle_event("change_image", _, %Socket{} = socket) do
    {:noreply, Current.update_image(socket)}
  end

  defp get_quiz(%Socket{assigns: %{quiz: %Quiz{} = quiz}}), do: quiz
  defp get_quiz(%Socket{assigns: %{quiz: %Changeset{data: %Quiz{} = quiz}}}), do: quiz

  defp set_region(%Socket{} = socket, ""), do: socket

  defp set_region(%Socket{} = socket, "" <> region) do
    assign(socket, :quiz, update_quiz(socket, %{"region" => region}))
  end

  defp update_quiz(%Socket{} = socket, changes) do
    socket
    |> validate_quiz(changes)
    |> case do
      # turn back into a changeset so that it works with Phoenix.HTML.FormData
      %Quiz{} = quiz -> Quiz.changeset(quiz, %{})
      %Changeset{} = changeset -> changeset
    end
  end

  defp validate_quiz(socket, changes) do
    socket
    |> get_quiz()
    |> Quiz.changeset(changes)
    |> Quiz.apply_valid_changes()
  end
end
