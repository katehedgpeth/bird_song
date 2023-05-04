defmodule BirdSong.Services.Ebird.RegionInfo do
  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_region_info,
    ets_opts: []

  alias BirdSong.{
    Services.Ebird.Regions.Region,
    Services.ThrottledCache,
    Services.Worker
  }

  alias __MODULE__.Response

  defstruct [:code, :name, :min_lat, :min_lon, :max_lat, :max_lon]

  @type t() :: %__MODULE__{
          code: String.t(),
          name: String.t(),
          min_lat: Float.t(),
          min_lon: Float.t(),
          max_lat: Float.t(),
          max_lon: Float.t()
        }
  @type request_data() :: {:region_info, Region.t()}

  @spec get_info(Region.t(), Worker.t()) :: Helpers.api_response(t())
  def get_info(%Region{} = region, worker) do
    with {:ok, %Response{data: %__MODULE__{} = info}} <- get({:region_info, region}, worker) do
      {:ok, info}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  OVERRIDABLE METHODS
  ##
  #########################################################

  # @impl ThrottledCache
  def data_file_name({:region_info, %Region{}} = request) do
    ets_key(request)
  end

  @impl ThrottledCache
  def endpoint({:region_info, %Region{code: region_code}}) do
    Path.join(["v2", "ref", "region", "info", region_code])
  end

  @impl ThrottledCache
  def ets_key({:region_info, %Region{code: code}}), do: code

  @impl ThrottledCache
  def params({:region_info, %Region{}}), do: %{"format" => "json"}

  @impl ThrottledCache
  def headers({:region_info, %Region{}}), do: [Ebird.token_header() | user_agent()]
end
