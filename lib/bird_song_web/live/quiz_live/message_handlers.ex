defmodule BirdSongWeb.QuizLive.MessageHandlers do
  require Logger
  use BirdSongWeb.QuizLive.Assign

  alias BirdSong.Services

  alias BirdSongWeb.QuizLive

  def handle_info(:get_region_species_codes, socket) do
    {:noreply, QuizLive.Services.get_region_species_codes(socket)}
  end

  def handle_info(
        {:get_recent_observations, tries: tries},
        %Socket{assigns: %{max_api_tries: max}} = socket
      )
      when tries >= max do
    {:noreply,
     socket
     |> Phoenix.LiveView.clear_flash()
     |> Phoenix.LiveView.put_flash(
       :error,
       "eBird is not responding to our requests at the moment. Please try again later."
     )}
  end

  ####################################
  ####################################
  ##  USED IN TESTS
  ##

  def handle_info({:register_render_listener, pid}, socket) do
    {:noreply,
     assign(
       socket,
       :render_listeners,
       [pid | socket.assigns[:render_listeners]]
     )}
  end

  def handle_info({:services, %Services{} = services}, socket) do
    {:noreply, assign(socket, :services, services)}
  end
end
