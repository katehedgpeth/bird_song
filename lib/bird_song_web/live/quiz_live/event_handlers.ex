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

  def handle_event("set_species_category", params, socket) do
    {:noreply, update_species_categories(socket, params)}
  end

  def handle_event(
        "start",
        %{"quiz" => changes},
        %Socket{} = socket
      ) do
    {:noreply, maybe_start_quiz(socket, changes)}
  end

  def handle_event("start", %{}, %Socket{assigns: %{birds: [], quiz: %Quiz{}}} = socket) do
    Process.send(self(), :get_region_species_codes, [])

    {:noreply, socket}
  end

  def handle_event("validate", %{"quiz" => changes}, %Socket{} = socket) do
    {:noreply, assign(socket, :filters, update_filters(socket, changes))}
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

  defp filter_birds({category_name, birds}, acc, selected_categories) do
    case Map.fetch!(selected_categories, category_name) do
      true -> [birds | acc]
      false -> acc
    end
  end

  defp get_quiz(%Socket{assigns: %{quiz: %Quiz{} = quiz}}), do: quiz
  defp get_quiz(%Socket{assigns: %{filters: %Changeset{data: %Quiz{} = quiz}}}), do: quiz

  defp set_quiz_birds(%Socket{assigns: assigns} = socket, %Quiz{} = quiz) do
    selected_categories = Map.fetch!(assigns, :species_categories)
    by_category = Map.fetch!(assigns, :birds_by_category)

    selected_birds =
      by_category
      |> Enum.reduce([], &filter_birds(&1, &2, selected_categories))
      |> List.flatten()

    assign(socket, :quiz, %{quiz | birds: selected_birds})
  end

  defp set_region(%Socket{} = socket, ""), do: socket

  defp set_region(%Socket{} = socket, "" <> region) do
    assign(socket, :filters, update_filters(socket, %{"region" => region}))
  end

  @spec maybe_start_quiz(Socket.t(), Map.t()) :: Socket.t()
  defp maybe_start_quiz(%Socket{} = socket, changes) do
    socket
    |> validate_quiz(changes)
    |> case do
      %Quiz{} = quiz ->
        socket
        |> set_quiz_birds(quiz)
        |> EtsTables.Assigns.remember_session()
        |> LiveView.push_redirect(to: "/quiz")

      %Changeset{} = changeset ->
        assign(socket, :filters, changeset)
    end
  end

  defp update_filters(%Socket{} = socket, changes) do
    socket
    |> validate_quiz(changes)
    |> case do
      # turn back into a changeset so that it works with Phoenix.HTML.FormData
      %Quiz{} = quiz -> Quiz.changeset(quiz, %{})
      %Changeset{} = changeset -> changeset
    end
  end

  defp update_species_categories(%Socket{assigns: assigns} = socket, %{"value" => category}) do
    LiveView.assign(
      socket,
      :species_categories,
      assigns
      |> Map.fetch!(:species_categories)
      |> Map.update!(category, &(not &1))
    )
  end

  defp validate_quiz(socket, changes) do
    socket
    |> get_quiz()
    |> Quiz.changeset(changes)
    |> Quiz.apply_valid_changes()
  end
end
