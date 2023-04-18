defmodule BirdSong.Services.Ebird.Regions do
  import __MODULE__.Region, only: [is_child_level: 1]

  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_regions,
    ets_opts: [],
    base_url: "https://api.ebird.org",
    data_folder_path: "data/regions",
    throttler: BirdSong.Services.RequestThrottler.EbirdAPI

  alias BirdSong.{Services.Ebird, Services.Helpers}
  alias __MODULE__.{Region, Response}

  @type exception() :: %{
          required(:__struct__) => atom(),
          required(:__exception__) => true,
          optional(atom()) => any()
        }
  @type request_args() :: [{:level, Region.level()}, {:parent, String.t()}]
  @type request_data() :: {:regions, request_args()}
  @type no_subregions_error() :: {:error, {:no_subregions, request_args()}}
  @type regions_response() ::
          {:ok, [Region.t()]}
          | no_subregions_error()
          | Helpers.api_error()

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec get_all(Service.t()) :: Helpers.api_response([Region.t()])
  def get_all!(service) do
    case get_all(service) do
      {:ok, [%Region{} | _] = regions} -> {:ok, regions}
      {:error, %{__exception__: true} = error} -> raise error
    end
  end

  def get_all(service) do
    with {:ok, countries} <- get_countries(service) do
      do_get_all(countries, [], service)
    end
  end

  @spec get_countries(atom | pid | BirdSong.Services.Service.t()) ::
          Helpers.api_response([Region.t()])
  def get_countries(server) do
    return_regions([level: :country, parent: "world"], server)
  end

  @spec get_subregions(Region.t(), Service.t(), Region.level()) :: regions_response()
  def get_subregions(
        %Region{code: "" <> region_code, level: :country},
        service,
        level
      )
      when is_child_level(level) do
    return_regions([level: level, parent: region_code], service)
  end

  def get_subregions(
        %Region{code: sub1_code, level: :subnational1} = sub1_region,
        service,
        :subnational2
      ) do
    "" <> country_code = Region.parse_parent_code(sub1_region)

    with {:ok, regions} <- return_regions([level: :subnational2, parent: country_code], service) do
      case Enum.filter(regions, &is_sub2_of_sub1(&1, sub1_code)) do
        [] -> {:error, {:no_subregions, level: :subnational2, parent: sub1_code}}
        [%Region{} | _] = sub2 -> {:ok, sub2}
      end
    end
  end

  @spec get_country(Region.t(), Service.t()) :: {:ok, [Region.t()]} | {:error, exception()}
  def get_country(%Region{level: :country} = country, service) do
    country
    |> get_subregions(service, :subnational1)
    |> get_country_subnational2(country, service)
  end

  defp get_country_subnational2(
         {:error, {:no_subregions, level: :subnational1, parent: _}},
         %Region{},
         %Service{}
       ) do
    {:ok, []}
  end

  defp get_country_subnational2({:error, %{__exception__: true} = error}, %Region{}, %Service{}) do
    {:error, error}
  end

  defp get_country_subnational2(
         {:ok, subnat_1},
         %Region{level: :country} = country,
         %Service{} = service
       ) do
    case get_subregions(country, service, :subnational2) do
      {:ok, subnat_2} ->
        {:ok, List.flatten([subnat_1, subnat_2])}

      {:error, {:no_subregions, _}} ->
        {:ok, subnat_1}

      {:error, %{__exception__: true} = error} ->
        {:error, error}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  OVERRIDABLE METHODS
  ##
  #########################################################

  def data_file_name({:regions, _} = request) do
    ets_key(request)
  end

  def endpoint({:regions, level: level, parent: parent}) do
    Path.join(["v2", "ref", "region", "list", Atom.to_string(level), parent])
  end

  def ets_key({:regions, level: :country, parent: "world"}), do: "all-countries"

  def ets_key({:regions, level: level, parent: parent}) do
    Enum.join([parent, Atom.to_string(level)], "-")
  end

  def params({:regions, _}), do: [{"format", "json"}]

  def headers({:regions, _}), do: [Ebird.token_header() | user_agent()]

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec return_regions(request_args(), Service.t()) ::
          regions_response()
  defp return_regions(args, %Service{} = service) do
    case get({:regions, args}, service) do
      {:ok, %Response{regions: [%Region{} | _] = regions}} -> {:ok, regions}
      {:ok, %Response{regions: []}} -> {:error, {:no_subregions, args}}
      {:error, %{__exception__: true} = error} -> {:error, error}
    end
  end

  defp do_get_all([], [%Region{} | _] = results, %Service{}) do
    {:ok, results}
  end

  defp do_get_all([%Region{} = region | rest], acc, %Service{} = service) do
    case get_country(region, service) do
      {:ok, []} ->
        do_get_all(rest, [region | acc], service)

      {:ok, regions} when is_list(regions) ->
        do_get_all(rest, Enum.reduce(regions, acc, &[&1 | &2]), service)

      {:error, %{__exception__: true} = error} ->
        {:error, error}
    end
  end

  defp is_sub2_of_sub1(%Region{code: sub2_code, level: :subnational2}, "" <> sub1_code) do
    String.starts_with?(sub2_code, sub1_code)
  end

  defp is_sub2_of_sub1(%Region{}, "" <> _) do
    false
  end
end
