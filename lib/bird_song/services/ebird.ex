defmodule BirdSong.Services.Ebird do
  use BirdSong.Services.Supervisor,
    base_url: "https://api.ebird.org",
    caches: [:Observations, :RegionSpeciesCodes, :Regions, :RegionInfo],
    other_children: [:RegionETS],
    use_data_folder?: true

  alias BirdSong.Services.Supervisor, as: Sup

  alias BirdSong.Services.Service

  alias __MODULE__.{
    Observations,
    Regions,
    RegionSpeciesCodes
  }

  #########################################################
  #########################################################
  ##
  ##  TYPESPECS
  ##
  #########################################################
  @type request_data() ::
          Observations.request_data()
          | Regions.request_data()
          | RegionInfo.request_data()
          | RegionSpeciesCodes.request_data()

  @type child_name() ::
          :Observations
          | :RegionInfo
          | :RegionETS
          | :RegionSpeciesCodes
          | :Regions
          | :RequestThrottler

  @type t() :: %__MODULE__{
          Observations: Service.t(),
          RegionInfo: Service.t(),
          RegionSpeciesCodes: Service.t(),
          Regions: Service.t()
        }

  @type opt() :: {:service_name, Sup.test_instance()}

  #########################################################
  #########################################################
  ##
  ##  CUSTOM ATTRIBUTES
  ##
  #########################################################

  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def token_header() do
    {"x-ebirdapitoken", @token}
  end
end
