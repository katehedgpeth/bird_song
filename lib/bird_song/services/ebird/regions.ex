defmodule BirdSong.Services.Ebird.Regions do
  use BirdSong.Services.ThrottledCache,
    ets_name: :ebird_regions,
    ets_opts: [],
    base_url: "https://api.ebird.org",
    data_folder_path: "data/regions",
    throttler: BirdSong.Services.RequestThrottler.EbirdAPI

  alias BirdSong.{Services, Services.Ebird}
  alias __MODULE__.{Region, Response}

  @type request_data() :: {:regions, level: Region.level(), country: String.t()}

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def get_all(server) do
    case get_countries(server) do
      {:ok, %Response{regions: regions}} ->
        Services.Tasks
        |> Task.Supervisor.async_stream(
          regions,
          __MODULE__,
          :get_country,
          [server],
          timeout: :infinity
        )
        |> Enum.into([])
    end
  end

  def get_countries(server) do
    get({:regions, level: :country, country: "world"}, server)
  end

  def get_subregions(level, "" <> country_code, server)
      when level in [:subnational1, :subnational2] do
    get({:regions, level: level, country: country_code}, server)
  end

  def get_country(%Region{code: code}, server) do
    Services.Tasks
    |> Task.Supervisor.async_stream(
      [:subnational1, :subnational2],
      __MODULE__,
      :get_subregions,
      [code, server],
      timeout: :infinity
    )
    |> Enum.into([])
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
end
