defmodule BirdSongWeb.Components.Filters.RegionBirds do
  alias BirdSongWeb.Components.Filters

  alias BirdSong.{
    Bird,
    Region,
    Services,
    Services.Ebird,
    Services.Helpers
  }

  @spec get_region_birds(Region.t() | String.t(), Filters.t()) ::
          [Filters.ByFamily.bird_state()]
          | {:error, :no_codes_for_region | :no_observations | Helpers.api_error()}

  def get_region_birds(%Region{code: code}, assigns) do
    get_region_birds(code, assigns)
  end

  def get_region_birds("" <> code, assigns) do
    do_get_region_birds(code, assigns.services, use_recent?: assigns.use_recent_observations?)
  end

  defp do_get_region_birds(
         "" <> region_code,
         %Services{} = services,
         use_recent?: false
       ) do
    with {:ok, birds} <- get_all_region_birds(region_code, services) do
      birds
    end
  end

  defp do_get_region_birds(
         "" <> region_code,
         %Services{} = services,
         use_recent?: true
       ) do
    with {:ok, all_birds} <- get_all_region_birds(region_code, services),
         {:ok, observations} <- get_recent_observations(region_code, services) do
      bird_map = Map.new(all_birds, &{&1.bird.species_code, &1})

      bird_map
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.difference(observations)
      |> Enum.reduce(bird_map, &set_disabled/2)
      |> Map.values()
    end
  end

  defp bird_state(%Bird{} = bird) do
    %{bird: bird, selected?: false, disabled?: false}
  end

  defp get_all_region_birds(region_code, %Services{ebird: %Ebird{RegionSpeciesCodes: worker}}) do
    region_code
    |> Ebird.RegionSpeciesCodes.get_codes(worker)
    |> case do
      {:error, error} ->
        {:error, error}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: []}} ->
        {:error, :no_codes_for_region}

      {:ok, %Ebird.RegionSpeciesCodes.Response{codes: codes}} ->
        {:ok,
         codes
         |> Bird.get_many_by_species_code()
         |> Enum.map(&bird_state/1)}
    end
  end

  defp get_recent_observations(region_code, %Services{ebird: %Ebird{Observations: worker}}) do
    region_code
    |> Ebird.Observations.get_recent_observations(worker)
    |> case do
      {:error, error} ->
        {:error, error}

      {:ok, %Ebird.Observations.Response{observations: []}} ->
        {:error, :no_observations}

      {:ok, %Ebird.Observations.Response{observations: observations}} ->
        {:ok,
         observations
         |> Enum.map(& &1.species_code)
         |> MapSet.new()}
    end
  end

  defp set_disabled(code, all_birds) do
    Map.update!(all_birds, code, &Map.replace!(&1, :disabled?, true))
  end
end
