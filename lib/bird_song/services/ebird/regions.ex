defmodule BirdSong.Services.Ebird.Regions do
  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_regions,
    ets_opts: [],
    base_url: "https://api.ebird.org",
    data_folder_path: "data/regions",
    throttler: BirdSong.Services.RequestThrottler.EbirdAPI

  alias BirdSong.{Services.Ebird, Services.Helpers}
  alias __MODULE__.{Region, Response}

  @type request_args() :: [{:level, Region.level()}, {:country, String.t()}]
  @type request_data() :: {:regions, request_args()}
  @type regions_response() :: {:ok, [Region.t()]} | Helpers.api_error()

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec get_all(Service.t()) :: Helpers.api_response([Region.t()])
  def get_all(service) do
    with {:ok, countries} <- get_countries(service) do
      do_get_all(countries, [], service)
    end
  end

  @spec get_countries(atom | pid | BirdSong.Services.Service.t()) ::
          Helpers.api_response([Region.t()])
  def get_countries(server) do
    return_regions([level: :country, country: "world"], server)
  end

  @spec get_subregions(Region.t(), Service.t(), Region.level()) :: regions_response()
  def get_subregions(%Region{level: :country, code: "" <> country_code}, service, level)
      when level in [:subnational1, :subnational2] do
    return_regions([level: level, country: country_code], service)
  end

  @spec get_country(Region.t(), Service.t()) :: regions_response()
  def get_country(%Region{level: :country} = country, service) do
    with {:ok, subnat_1} <- get_subregions(country, service, :subnational1),
         {:ok, subnat_2} <- get_subregions(country, service, :subnational2) do
      {:ok, Enum.concat(subnat_1, subnat_2)}
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

  def endpoint({:regions, level: level, country: country}) do
    Path.join(["v2", "ref", "region", "list", Atom.to_string(level), country])
  end

  def ets_key({:regions, level: :country, country: "world"}), do: "all-countries"

  def ets_key({:regions, level: level, country: country}) do
    Enum.join([country, Atom.to_string(level)], "-")
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
    with {:ok, %Response{regions: regions}} <- get({:regions, args}, service) do
      {:ok, regions}
    end
  end

  defp do_get_all([], [%Region{} | _] = results, %Service{}) do
    {:ok, results}
  end

  defp do_get_all([%Region{} = region | rest], acc, %Service{} = service) do
    case apply(__MODULE__, :get_country, [region, service]) do
      {:ok, regions} when is_list(regions) ->
        do_get_all(rest, Enum.reduce(regions, acc, &[&1 | &2]), service)

      {:error, error} ->
        {:error, error}
    end
  end
end
