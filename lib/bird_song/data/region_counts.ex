defmodule BirdSong.Data.RegionCounts do
  alias BirdSong.{
    Services.Worker,
    Services.Ebird.Regions,
    Services.Ebird.Regions.Region
  }

  defstruct country_counts: %{},
            country_regions: %{},
            total_countries: :not_calculated,
            total_regions: :not_calculated,
            total_subnational1: :not_calculated,
            total_subnational2: :not_calculated

  @type by_level(typ) :: %{
          optional(Region.level()) => typ
        }

  @type by_country(typ) :: %{String.t() => by_level(typ)}

  @type t() :: %__MODULE__{
          country_counts: by_country(integer()),
          country_regions: by_country([Region.t()]),
          total_countries: integer() | :not_calculated,
          total_regions: integer() | :not_calculated,
          total_subnational1: integer() | :not_calculated,
          total_subnational2: integer() | :not_calculated
        }

  @spec get(Worker.t(), %{optional(:region) => String.t()}) ::
          Regions.region_response()
  def get(%Worker{module: Regions} = service, %{
        region: "" <> parent_region
      }) do
    %{"code" => parent_region, "name" => :unknown}
    |> Region.parse()
    |> load_subregions(service)
    |> do_get()
  end

  def get(%Worker{module: Regions} = service, %{}) do
    service
    |> Regions.get_all()
    |> do_get()
  end

  defp count_countries(%__MODULE__{} = data, %{} = by_country) do
    country_count =
      case Map.pop(by_country, "world") do
        {%{country: countries}, %{}} ->
          length(countries)

        {nil, %{} = by_country} ->
          Kernel.map_size(by_country)
      end

    %{data | total_countries: country_count}
  end

  defp count_subregions(%__MODULE__{} = data, %{} = by_country, level) do
    by_country
    |> Enum.map(&ensure_subregion_lists/1)
    |> Enum.reduce(data, &do_count_subregions(&1, &2, level))
  end

  @spec do_count_subregions({String.t(), by_level([Region.t()])}, t(), Region.level()) :: t()
  defp do_count_subregions(
         {"" <> country_code, country_regions},
         %__MODULE__{} = data,
         level
       ) do
    subregions = Map.fetch!(country_regions, level)

    data
    |> Map.update!(:"total_#{level}", &update_total_count(&1, subregions))
    |> Map.update!(
      :country_counts,
      &update_country_counts(&1, country_code, subregions, level)
    )
  end

  defp do_get({:ok, regions}) do
    %{data: data, grouped: %{} = by_country} = group_by_country(regions, %__MODULE__{})

    %{data | country_regions: by_country}
    |> count_countries(by_country)
    |> count_subregions(by_country, :subnational1)
    |> count_subregions(by_country, :subnational2)
  end

  @spec ensure_subregion_lists({String.t(), by_level([Region.t()])}) ::
          {String.t(), by_level([Region.t()])}
  defp ensure_subregion_lists({country_code, by_level}) do
    {country_code,
     by_level
     |> Map.put_new(:subnational1, [])
     |> Map.put_new(:subnational2, [])}
  end

  @spec group_by_country([Region.t()], t()) :: %{data: t(), grouped: by_country([Region.t()])}
  defp group_by_country([%Region{} | _] = regions, %__MODULE__{} = data) do
    %{
      data: Map.replace!(data, :total_regions, length(regions)),
      grouped:
        regions
        |> Enum.group_by(&Region.parse_country_code(&1))
        |> Enum.map(&group_by_level/1)
        |> Enum.into(%{})
    }
  end

  defp group_by_level({"" <> country_code, regions}) do
    {country_code, Enum.group_by(regions, & &1.level)}
  end

  @spec load_subregions(Region.t() | {:error, any()}, Worker.t()) :: Regions.regions_response()
  defp load_subregions({:error, error}, %Worker{}) do
    {:error, error}
  end

  defp load_subregions(%Region{code: "world"}, %Worker{} = service) do
    Regions.get_all(service)
  end

  defp load_subregions(%Region{level: :country} = country, %Worker{} = service) do
    country
    |> Regions.get_country(service)
    |> do_load_subregions(country)
  end

  defp load_subregions(%Region{level: :subnational1} = region, %Worker{} = service) do
    region
    |> Regions.get_subregions(service, :subnational2)
    |> do_load_subregions(region)
  end

  defp load_subregions(%Region{level: :subnational2} = region, %Worker{}) do
    {:ok, [region]}
  end

  defp do_load_subregions({:ok, [%Region{} | _] = regions}, %Region{} = parent) do
    {:ok, [parent | regions]}
  end

  defp do_load_subregions({:error, {:no_subregions, _}}, %Region{} = parent) do
    {:ok, [parent]}
  end

  defp do_load_subregions({:error, error}, %Region{}) do
    {:error, error}
  end

  defp update_country_counts(
         %{} = country_counts,
         "" <> country_code,
         regions,
         level
       )
       when is_list(regions) and level in [:subnational1, :subnational2] do
    count = length(regions)

    Map.update(
      country_counts,
      country_code,
      %{level => count},
      &Map.put(&1, level, count)
    )
  end

  defp update_total_count(:not_calculated, region_list) do
    update_total_count(0, region_list)
  end

  defp update_total_count(prev_count, region_list) when is_list(region_list) do
    prev_count + length(region_list)
  end
end
