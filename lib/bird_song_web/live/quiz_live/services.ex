defmodule BirdSongWeb.QuizLive.Services do
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.Ebird
  }

  alias BirdSongWeb.QuizLive

  def get_region_species_codes(%Socket{} = socket) do
    socket
    |> get_region()
    |> Ebird.RegionSpeciesCodes.get_codes(get_server(socket, :region_species_codes))
    |> case do
      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}} ->
        get_birds_from_codes(socket, codes)

      {:error, _} ->
        socket
    end
  end

  defp get_birds_from_codes(%Socket{} = socket, ["" <> _ | _] = species_codes) do
    species_codes
    |> Bird.get_many_by_species_code()
    |> case do
      [%Bird{} | _] = birds ->
        socket
        |> Phoenix.LiveView.assign(:birds, Enum.shuffle(birds))
        |> QuizLive.assign_next_bird()

        # [] ->
        #   socket
        #   |> Phoenix.LiveView.put_flash(
        #     :warning,
        #     "Sorry, there do not appear to be any known birds in that region. Please choose a different or broader region."
        #   )
    end
  end

  defp get_region(%Socket{assigns: %{quiz: %Quiz{region: region}}}), do: region

  defp get_server(%Socket{assigns: %{services: %Services{} = services}}, service_name)
       when is_atom(service_name) do
    services
    |> Map.fetch!(service_name)
    |> Map.fetch!(:whereis)
  end
end
