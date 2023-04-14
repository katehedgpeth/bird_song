defmodule BirdSong.Services.Ebird.RegionInfo do
  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_region_info,
    ets_opts: [],
    base_url: "https://api.ebird.org",
    data_folder_path: "data/region_info",
    throttler: BirdSong.Services.RequestThrottler.EbirdAPI

  alias BirdSong.{
    Services.Service,
    Services.Ebird.Regions.Region
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

  @spec get_info(Region.t(), Service.t()) :: Helpers.api_response(t())
  def get_info(%Region{} = region, service) do
    with {:ok, %Response{data: %__MODULE__{} = info}} <- get({:region_info, region}, service) do
      {:ok, info}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  OVERRIDABLE METHODS
  ##
  #########################################################

  def data_file_name({:region_info, %Region{}} = request) do
    ets_key(request)
  end

  def endpoint({:region_info, %Region{code: region_code}}) do
    Path.join(["v2", "ref", "region", "info", region_code])
  end

  def ets_key({:region_info, %Region{code: code}}), do: code

  def params({:region_info, %Region{}}), do: %{"format" => "json"}

  def headers({:region_info, %Region{}}), do: [Ebird.token_header() | user_agent()]
end
