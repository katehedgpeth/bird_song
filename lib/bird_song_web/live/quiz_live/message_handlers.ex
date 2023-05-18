defmodule BirdSongWeb.QuizLive.MessageHandlers do
  require Logger

  alias Phoenix.LiveView

  alias BirdSong.{
    Accounts,
    Services
  }

  def handle_info({:start, filters}, socket) do
    %{quiz: %BirdSong.Quiz{}} =
      socket.assigns.user.id
      |> Accounts.update_current_quiz!(Map.new(filters))

    {:noreply, LiveView.push_redirect(socket, to: "/quiz")}
  end

  # -------- IGNORED MESSAGES ------------
  def handle_info(:change_region, socket), do: ignore_message(socket)
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
