defmodule BirdSongWeb.QuizLive.EventHandlers do
  use BirdSongWeb.QuizLive.Assign

  alias Phoenix.{
    LiveView,
    LiveView.Socket
  }

  alias Ecto.Changeset

  alias BirdSong.{
    Bird,
    Quiz
  }

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.Current,
    QuizLive.EtsTables,
    QuizLive.Visibility
  }

  @spec handle_event(String.t(), Map.t(), Socket.t()) ::
          {:noreply, Socket.t()} | {:reply, map(), Socket.t()}
  def handle_event("set_region", %{} = params, %Socket{} = socket) do
    {:noreply,
     socket
     |> set_region(params)
     |> get_region_codes()}
  end

  def handle_event("include?", %{"category" => _} = params, socket) do
    {:noreply, update_species_categories(socket, params)}
  end

  def handle_event(
        "start",
        %{},
        %Socket{} = socket
      ) do
    {:noreply, start_quiz(socket)}
  end

  def handle_event("next", _, %Socket{} = socket) do
    {:noreply,
     socket
     |> QuizLive.reset_state()
     |> QuizLive.assign_next_bird()}
  end

  def handle_event("change", %{"element" => element}, %Socket{} = socket) do
    {
      :noreply,
      Current.update_resource(socket, String.to_existing_atom(element))
    }
  end

  def handle_event("toggle_visibility", %{"element" => "answer"}, %Socket{} = socket) do
    {:noreply,
     socket
     |> Visibility.toggle(:image)
     |> Visibility.toggle(:answer)}
  end

  def handle_event("toggle_visibility", %{"element" => element}, %Socket{} = socket) do
    {:noreply, Visibility.toggle(socket, String.to_existing_atom(element))}
  end

  def handle_event("toggle_visibility", %{"category" => category}, %Socket{} = socket) do
    {:noreply, Visibility.toggle(socket, [:category_filters, category])}
  end

  defp set_quiz_birds(%Socket{assigns: assigns} = socket, %Quiz{} = quiz) do
    selected_birds =
      assigns
      |> Map.fetch!(:birds_by_category)
      |> Enum.map(fn {_category, birds} -> birds end)
      |> List.flatten()
      |> Enum.filter(& &1[:selected?])
      |> Enum.map(& &1[:bird])
      |> case do
        [] -> Map.fetch!(assigns, :birds)
        [_ | _] = selected -> selected
      end
      |> Enum.sort_by(& &1.common_name, :asc)

    assign(socket, :quiz, %{quiz | birds: selected_birds})
  end

  defp set_region(%Socket{} = socket, %{"quiz" => %{"region" => region}}) do
    assign(
      socket,
      :filters,
      socket.assigns[:filters]
      |> case do
        %Quiz{} = quiz -> quiz
        %Changeset{data: data} -> data
      end
      |> Quiz.changeset(%{region: region})
      |> Quiz.apply_valid_changes()
      # |> IO.inspect(label: :filters_after_changes)
    )
  end

  defp get_region_codes(%Socket{} = socket) do
    case socket.assigns[:filters] do
      %Quiz{} ->
        QuizLive.Services.assign_region_species_codes(socket)

      %Changeset{
        changes: %{region: region},
        errors: [{:region, {"unknown" <> _, []}} | _]
      } ->
        LiveView.put_flash(socket, "error", region <> " is not a known birding region")

      %Changeset{
        errors: [{:region, {"can't be blank", _}} | []]
      } ->
        LiveView.put_flash(socket, "error", "Please enter a region")

        # _ ->
        #   socket
    end
  end

  @spec start_quiz(Socket.t()) :: Socket.t()
  defp start_quiz(%Socket{} = socket) do
    socket
    |> set_quiz_birds(socket.assigns[:filters])
    |> EtsTables.Assigns.remember_session()
    |> LiveView.push_redirect(to: "/quiz")
  end

  defp update_category_birds(birds, %{"bird" => name, "category" => _}) do
    Enum.map(birds, fn
      %{bird: %Bird{common_name: ^name}, selected?: _} = bird ->
        %{bird | selected?: not bird[:selected?]}

      %{bird: %Bird{}, selected?: _} = bird ->
        bird
    end)
  end

  defp update_category_birds(birds, %{"category" => _}) do
    selected? = Enum.all?(birds, & &1[:selected?])
    Enum.map(birds, &%{&1 | selected?: not selected?})
  end

  defp update_species_categories(
         %Socket{assigns: assigns} = socket,
         %{"category" => category} = params
       ) do
    LiveView.assign(
      socket,
      :birds_by_category,
      assigns
      |> Map.fetch!(:birds_by_category)
      |> Map.update!(category, &update_category_birds(&1, params))
    )
  end
end
