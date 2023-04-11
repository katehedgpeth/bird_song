defmodule BirdSongWeb.QuizLive.Services do
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.Ebird
  }

  def get_region_species_codes(%Socket{} = socket) do
    socket
    |> get_region()
    |> do_get_region_species_codes(socket)
  end

  defp build_species_category_dict(birds_by_category) do
    birds_by_category
    |> Enum.map(fn {category, _} -> {category, false} end)
    |> Enum.into(%{})
  end

  defp do_get_region_species_codes({:ok, "" <> region}, socket) do
    region
    |> Ebird.RegionSpeciesCodes.get_codes(get_server(socket, :region_species_codes))
    |> case do
      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}} ->
        get_birds_from_codes(socket, codes)

      {:error, _} ->
        socket
    end
  end

  defp do_get_region_species_codes({:error, :not_set}, socket) do
    socket
  end

  defp get_birds_from_codes(%Socket{} = socket, []) do
    socket
  end

  defp get_birds_from_codes(%Socket{} = socket, ["" <> _ | _] = species_codes) do
    species_codes
    |> Bird.get_many_by_species_code()
    |> case do
      [%Bird{} | _] = birds ->
        by_category = Enum.group_by(birds, &Bird.family_name/1)

        socket
        |> Phoenix.LiveView.assign(:birds, Enum.shuffle(birds))
        |> Phoenix.LiveView.assign(:species_categories, build_species_category_dict(by_category))
        |> Phoenix.LiveView.assign(:birds_by_category, by_category)

      [] ->
        socket
        |> Phoenix.LiveView.assign(:birds, [])
        |> Phoenix.LiveView.put_flash(
          :warning,
          "Sorry, there do not appear to be any known birds in that region. Please choose a different or broader region."
        )
    end
  end

  defp get_region(%Socket{assigns: assigns}) do
    assigns
    |> Map.fetch!(:filters)
    |> Quiz.get_region()
  end

  defp get_server(%Socket{assigns: %{services: %Services{} = services}}, service_name)
       when is_atom(service_name) do
    services
    |> Map.fetch!(service_name)
    |> Map.fetch!(:whereis)
  end
end
