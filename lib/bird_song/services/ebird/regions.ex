defmodule BirdSong.Services.Ebird.Regions do
  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_regions,
    ets_opts: []

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Region,
    Services.Helpers,
    Services.ThrottledCache,
    Services.Worker
  }

  alias __MODULE__.Response

  import Region, only: [is_child_level: 1]

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

  @spec get_all!(Worker.t()) :: {:ok, [Region.t()]}
  def get_all!(worker) do
    case get_all(worker) do
      {:ok, [%Region{} | _] = regions} -> {:ok, regions}
      {:error, %{__exception__: true} = error} -> raise error
    end
  end

  @spec get_all(Worker.t()) :: Helpers.api_response([Region.t()])
  def get_all(worker) do
    with {:ok, countries} <- get_countries(worker) do
      do_get_all(countries, [], worker)
    end
  end

  @spec get_countries(Worker.t()) ::
          Helpers.api_response([Region.t()])
  def get_countries(worker) do
    return_regions([level: :country, parent: "world"], worker)
  end

  @spec get_subregions(Region.t(), Worker.t(), Region.level()) :: regions_response()
  def get_subregions(
        %Region{code: "" <> region_code, level: :country},
        worker,
        level
      )
      when is_child_level(level) do
    return_regions([level: level, parent: region_code], worker)
  end

  def get_subregions(
        %Region{code: sub1_code, level: :subnational1} = sub1_region,
        worker,
        :subnational2
      ) do
    "" <> country_code = Region.parse_parent_code(sub1_region)

    with {:ok, regions} <- return_regions([level: :subnational2, parent: country_code], worker) do
      case Enum.filter(regions, &is_sub2_of_sub1(&1, sub1_code)) do
        [] -> {:error, {:no_subregions, level: :subnational2, parent: sub1_code}}
        [%Region{} | _] = sub2 -> {:ok, sub2}
      end
    end
  end

  @spec get_country(Region.t(), Worker.t()) :: {:ok, [Region.t()]} | {:error, exception()}
  def get_country(%Region{level: :country} = country, worker) do
    country
    |> get_subregions(worker, :subnational1)
    |> get_country_subnational2(country, worker)
  end

  defp get_country_subnational2(
         {:error, {:no_subregions, level: :subnational1, parent: _}},
         %Region{},
         %Worker{}
       ) do
    {:ok, []}
  end

  defp get_country_subnational2({:error, %{__exception__: true} = error}, %Region{}, %Worker{}) do
    {:error, error}
  end

  defp get_country_subnational2(
         {:ok, subnat_1},
         %Region{level: :country} = country,
         %Worker{} = worker
       ) do
    case get_subregions(country, worker, :subnational2) do
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

  @impl ThrottledCache
  def endpoint({:regions, level: level, parent: parent}) do
    Path.join(["v2", "ref", "region", "list", Atom.to_string(level), parent])
  end

  @impl ThrottledCache
  def ets_key({:regions, level: :country, parent: "world"}), do: "all-countries"

  def ets_key({:regions, level: level, parent: parent}) do
    Enum.join([parent, Atom.to_string(level)], "-")
  end

  @impl ThrottledCache
  def message_details({:regions, opts}) do
    Map.new(opts)
  end

  @impl ThrottledCache
  def params({:regions, _}), do: [{"format", "json"}]

  @impl ThrottledCache
  def headers({:regions, _}), do: [Ebird.token_header() | user_agent()]

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec return_regions(request_args(), Worker.t()) ::
          regions_response()
  defp return_regions(args, worker) do
    case get({:regions, args}, worker) do
      {:ok, %Response{regions: [%Region{} | _] = regions}} -> {:ok, regions}
      {:ok, %Response{regions: []}} -> {:error, {:no_subregions, args}}
      {:error, %{__exception__: true} = error} -> {:error, error}
    end
  end

  defp do_get_all([], [%Region{} | _] = results, %Worker{}) do
    {:ok, results}
  end

  defp do_get_all([%Region{} = region | rest], acc, %Worker{} = worker) do
    case get_country(region, worker) do
      {:ok, []} ->
        do_get_all(rest, [region | acc], worker)

      {:ok, regions} when is_list(regions) ->
        do_get_all(rest, Enum.reduce(regions, acc, &[&1 | &2]), worker)

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
