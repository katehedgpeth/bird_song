defmodule BirdSongWeb.QuizLive.MessageHandlers do
  require Logger

  alias Phoenix.LiveView

  alias BirdSong.{
    Services
  }

  def handle_info({:start, filters}, socket) do
    quiz =
      filters
      |> Keyword.put(:session_id, socket.assigns.session_id)
      |> BirdSong.Quiz.create!()

    BirdSong.PubSub.broadcast(socket, {:quiz_created, quiz.id})

    {:noreply, LiveView.push_redirect(socket, to: "/quiz")}
  end

  # -------- IGNORED MESSAGES ------------
  def handle_info(:change_region, socket), do: ignore_message(socket)
  def handle_info({:quiz_created, _}, socket), do: ignore_message(socket)
  def handle_info({:region_selected, %BirdSong.Region{}}, socket), do: ignore_message(socket)

  ####################################
  ####################################
  ##  USED IN TESTS
  ##

  if Mix.env() === :test do
    def handle_info({:services, %Services{} = services}, socket) do
      {:noreply, LiveView.assign(socket, :services, services)}
    end

    def handle_call(:socket, _, socket) do
      {:reply, socket, socket}
    end
  end

  defp ignore_message(socket), do: {:noreply, socket}
end
