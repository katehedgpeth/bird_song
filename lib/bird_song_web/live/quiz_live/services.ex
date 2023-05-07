defmodule BirdSongWeb.QuizLive.Services do
  require BirdSong.Services

  alias BirdSong.Services.Worker
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Bird,
    Quiz,
    Services,
    Services.Ebird,
    Services.Ebird.Region,
    Services.Helpers
  }

  @no_birds_error "
  Sorry, there do not appear to be any known birds in that region.
  Please choose a different or broader region.
  "

  @spec assign_region_species_codes(Socket.t()) :: Socket.t()
  def assign_region_species_codes(%Socket{} = socket) do
    case get_region(socket) do
      {:ok, %Region{} = region} ->
        worker = get_worker(socket, :ebird, :RegionSpeciesCodes)

        region
        |> Ebird.RegionSpeciesCodes.get_codes(worker)
        |> do_assign_region_species_codes(socket)

      {:error, :not_set} ->
        socket
    end
  end

  defp build_species_category_dict(birds_by_category) do
    birds_by_category
    |> Enum.map(fn {category, _} -> {category, false} end)
    |> Enum.into(%{})
  end

  defp do_assign_region_species_codes(
         {:ok, %Ebird.RegionSpeciesCodes.Response{codes: [], region: region}},
         socket
       ) do
    Helpers.log([message: "no_species_codes_returned", region: region], __MODULE__, :warning)
    Phoenix.LiveView.put_flash(socket, :error, @no_birds_error)
  end

  defp do_assign_region_species_codes(
         {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}},
         socket
       ) do
    get_birds_from_codes(socket, codes)
  end

  defp do_assign_region_species_codes(
         {:error, {:bad_response, %HTTPoison.Response{status_code: 400}}},
         socket
       ) do
    Phoenix.LiveView.put_flash(
      socket,
      :error,
      "That is not a valid region code"

      # "We're sorry, but our service is not available at the moment. Please try again later."
    )
  end

  defp do_assign_region_species_codes({:error, _}, socket) do
    Phoenix.LiveView.put_flash(
      socket,
      :error,
      "We're sorry, but our service is not available at the moment. Please try again later."
    )
  end

  defp do_get_region_species_codes({:error, :not_set}, socket) do
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
          :error,
          @no_birds_error
        )
    end
  end

  @spec get_region(Socket.t()) :: {:ok, Region.t()} | {:error, :not_set}
  defp get_region(%Socket{assigns: assigns}) do
    assigns
    |> Map.fetch!(:filters)
    |> Quiz.get_region()
  end

  @spec get_worker(Socket.t(), Services.service_key(), atom()) :: Worker.t()
  defp get_worker(%Socket{assigns: %{services: %Services{} = services}}, service_key, worker_atom)
       when BirdSong.Services.is_service_key(service_key) do
    services
    |> Map.fetch!(service_key)
    |> Map.fetch!(worker_atom)
  end
end
