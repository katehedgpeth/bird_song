defmodule BirdSongWeb.QuizLive.EventHandlers do
  use BirdSongWeb.QuizLive.Assign
  alias Ecto.Changeset
  alias BirdSong.Quiz
  alias BirdSongWeb.{QuizLive, QuizLive.Current}

  def handle_event(
        "start",
        %{"quiz" => changes},
        %Socket{assigns: %{quiz: quiz}} = socket
      ) do
    case Quiz.changeset(quiz, changes) do
      %Changeset{errors: [], data: data} ->
        Process.send(self(), :get_region_species_codes, [])
        {:noreply, assign(socket, :quiz, data)}

      %Changeset{} = changeset ->
        {:noreply, assign(socket, :quiz, changeset)}
    end
  end

  def handle_event("start", %{}, %Socket{} = socket) do
    Process.send(self(), :get_region_species_codes, [])

    {:noreply,
     assign(
       socket,
       :quiz,
       Quiz.default_changeset() |> Map.fetch!(:data)
     )}
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{assigns: %{quiz: quiz}} = socket) do
    {:noreply, assign(socket, :quiz, Quiz.changeset(quiz, changes))}
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
end
