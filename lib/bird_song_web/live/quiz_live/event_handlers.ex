defmodule BirdSongWeb.QuizLive.EventHandlers do
  use BirdSongWeb.QuizLive.Assign
  alias Phoenix.LiveView
  alias Ecto.Changeset
  alias BirdSong.Quiz

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.Current,
    QuizLive.EtsTables
  }

  # defdelegated from QuizLive
  @spec handle_event(String.t(), Map.t(), Socket.t()) ::
          {:noreply, Socket.t()} | {:reply, map(), Socket.t()}
  def handle_event("set_region", %{}, %Socket{} = socket) do
    {:noreply, set_region_and_get_codes(socket)}
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

  defp filter_birds(assigns, selected_categories) do
    assigns
    |> Map.fetch!(:birds_by_category)
    |> Enum.reduce([], &do_filter_birds(&1, &2, selected_categories))
    |> List.flatten()
    |> Enum.sort_by(& &1.common_name, :asc)
  end

  defp do_filter_birds({category_name, birds}, acc, selected_categories) do
    case MapSet.member?(selected_categories, category_name) do
      true -> [birds | acc]
      false -> acc
    end
  end

  defp get_quiz(%Socket{assigns: %{quiz: %Quiz{} = quiz}}), do: quiz
  defp get_quiz(%Socket{assigns: %{filters: %Changeset{data: %Quiz{} = quiz}}}), do: quiz

  defp set_quiz_birds(%Socket{assigns: assigns} = socket, %Quiz{} = quiz) do
    selected_birds =
      assigns
      |> Map.fetch!(:species_categories)
      |> Enum.filter(fn {_name, selected?} -> selected? end)
      |> Enum.map(fn {name, true} -> name end)
      |> case do
        [] -> Map.fetch!(assigns, :birds)
        [_ | _] = selected -> filter_birds(assigns, MapSet.new(selected))
      end
      |> Enum.sort_by(& &1.common_name, :asc)

    assign(socket, :quiz, %{quiz | birds: selected_birds})
  end

  defp set_region_and_get_codes(%Socket{} = socket) do
    case socket.assigns[:filters] do
      %Changeset{
        valid?: true,
        data: %Quiz{
          region: "" <> _
        }
      } ->
        QuizLive.Services.assign_region_species_codes(socket)

      %Changeset{
        changes: %{region: region},
        valid?: false,
        errors: [{:region, {"unknown" <> _, []}} | _]
      } ->
        LiveView.put_flash(socket, "error", region <> " is not a known birding region")

      %Changeset{
        errors: [{:region, {"Can't be blank", _}} | []]
      } ->
        LiveView.put_flash(socket, "error", "Please enter a region")

      _ ->
        socket
    end
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
