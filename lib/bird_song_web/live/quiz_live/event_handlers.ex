defmodule BirdSongWeb.QuizLive.EventHandlers do
  alias Phoenix.{
    LiveView.Socket
  }

  alias BirdSong.{
    Bird,
    Quiz,
    Repo
  }

  alias BirdSongWeb.{
    QuizLive,
    QuizLive.Assign,
    QuizLive.Current,
    QuizLive.Visibility
  }

  @spec handle_event(String.t(), Map.t(), Socket.t()) ::
          {:noreply, Socket.t()} | {:reply, map(), Socket.t()}

  def handle_event("next", _, %Socket{} = socket) do
    {:noreply,
     socket.assigns
     |> Assign.assigns_to_struct()
     |> QuizLive.reset_state()
     |> QuizLive.assign_next_bird()
     |> Assign.assign(socket)}
  end

  def handle_event("change", %{"element" => element}, %Socket{} = socket) do
    {
      :noreply,
      socket.assigns
      |> Assign.assigns_to_struct()
      |> Current.update_resource(String.to_existing_atom(element))
      |> Assign.assign(socket)
    }
  end

  def handle_event("submit_answer", %{"bird" => bird_id}, %Socket{} = socket) do
    {:noreply, check_answer(socket, String.to_integer(bird_id))}
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

  defp check_answer(%Socket{} = socket, submitted) when is_integer(submitted) do
    Assign.update_assigns(
      socket,
      &Current.assign_answer(
        &1,
        Quiz.Answer.submit!(%{
          quiz: socket.assigns.quiz,
          correct_bird: socket.assigns.current.bird,
          submitted_bird: Repo.get!(Bird, submitted)
        })
      )
    )
  end
end
