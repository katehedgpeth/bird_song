defmodule BirdSong.Services.Ebird.Regions.Region.MalformedRegionCodeError do
  defexception [:code]

  @type t() :: %__MODULE__{
          code: String.t()
        }

  def message(%__MODULE__{code: code}) do
    """
    Malformed region code: #{code}

    Expected region code to be in one of these forms:
      country -> XX
      subnational1 -> XX-XX or XX-XXX
      subnational2 -> XX-XX-XXX or XX-XXX-XXX
    """
  end
end

defmodule BirdSong.Services.Ebird.Regions.Region do
  alias __MODULE__.MalformedRegionCodeError
  alias BirdSong.Services.Ebird.Regions.RegionETS

  defstruct [:code, :name, :level]

  @type level() :: :country | :subnational1 | :subnational2

  @type t() :: %__MODULE__{
          code: String.t(),
          name: String.t() | :unknown,
          level: level()
        }

  @sublevels %{
    country: :subnational1,
    subnational1: :subnational2
  }

  @type get_parent_return() :: {:ok, t()} | {:error, :not_found}

  defguard is_region_level(level) when level in [:country, :subnational1, :subnational2]
  defguard is_child_level(level) when level in [:subnational1, :subnational2]
  defguard is_parent_level(level) when level in [:country, :subnational1]

  @spec get_parent(BirdSong.Services.Ebird.Regions.Region.t()) :: get_parent_return()
  def get_parent(%__MODULE__{} = region) do
    get_parent(region, :country)
  end

  @spec get_parent(BirdSong.Services.Ebird.Regions.Region.t(), level()) ::
          get_parent_return()
  def get_parent(%__MODULE__{} = region, level) when level in [:country, :subnational1] do
    get_parent(region, level, RegionETS)
  end

  @spec get_parent(BirdSong.Services.Ebird.Regions.Region.t(), level(), GenServer.server()) ::
          get_parent_return()
  def get_parent(%__MODULE__{level: :country}, _parent_level, _) do
    {:error, :no_parent}
  end

  def get_parent(%__MODULE__{level: child_level} = region, :country, ets_server)
  when is_child_level(child_level) do
    region
    |> parse_country_code()
    |> RegionETS.get(ets_server)
  end

  def get_parent(%__MODULE__{level: :subnational2, code: code}, :subnational1, ets_server) do
    code
    |> parse_subnational1_code()
    |> RegionETS.get(ets_server)
  end

  @spec get_parent!(BirdSong.Services.Ebird.Regions.Region.t()) ::
          BirdSong.Services.Ebird.Regions.Region.t()

  def get_parent!(%__MODULE__{} = region, level \\ :country, server \\ RegionETS) do
    region
    |> get_parent(level, server)
    |> raise_if_error!()
  end

  defp raise_if_error!({:error, error}) do
    raise error
  end

  defp raise_if_error!({:ok, response}), do: response

  def parse(%{"code" => code, "name" => name}) do
    with {:ok, level} <- parse_level(code) do
      %__MODULE__{
        code: code,
        level: level,
        name: name
      }
    end
  end

  def parse!(%{"code" => code, "name" => name}) do
    struct(__MODULE__, name: name, code: code, level: parse_level!(code))
  end

  def parse_country_code(%__MODULE__{code: code}) do
    parse_country_code(code)
  end

  def parse_country_code(<<country_code::binary-size(2)>>) do
    country_code
  end

  def parse_country_code(<<country_code::binary-size(2), _::binary>>) do
    country_code
  end

  def parse_country_code("" <> code) do
    {:error, MalformedRegionCodeError.exception(code: code)}
  end

  @spec parse_level(String.t()) :: {:ok, level()} | {:error, MalformedRegionCode.t()}
  def parse_level(<<_country_code::binary-size(2)>>) do
    {:ok, :country}
  end

  def parse_level(<<_country_code::binary-size(2), "-", subnational::binary>> = region_code) do
    case String.split(subnational, "-", trim: true) do
      ["" <> _, "" <> _] ->
        {:ok, :subnational2}

      ["" <> _] ->
        {:ok, :subnational1}

      _ ->
        {:error, MalformedRegionCodeError.exception(code: region_code)}
    end
  end

  def parse_level(code) do
    {:error, MalformedRegionCodeError.exception(code: code)}
  end

  def parse_level!(code) do
    case parse_level(code) do
      {:ok, level} -> level
      {:error, error} -> raise error
    end
  end

  def parse_parent_code(%__MODULE__{level: :country}) do
    "world"
  end

  def parse_parent_code(%__MODULE__{code: code, level: :subnational1}) do
    parse_country_code(code)
  end

  def parse_parent_code(%__MODULE__{code: code, level: :subnational2}, parent_level) do
    case parent_level do
      :country ->
        parse_country_code(code)

      :subnational1 ->
        [country, sub1, _] = String.split(code, "-")
        Enum.join([country, sub1], "-")
    end
  end

  def parse_sublevel("" <> parent_level) do
    case parse_level(parent_level) do
      {:ok, level} -> parse_sublevel(level)
      {:error, error} -> {:error, error}
    end
  end

  def parse_sublevel(level) when is_atom(level) do
    Map.fetch(@sublevels, level)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp parse_subnational1_code(
         <<country::binary-size(2), "-", subnational1::binary-size(2), "-",
           _subnational_2::binary-size(2)>>
       ) do
    Enum.join([country, subnational1], "-")
  end

  defp parse_subnational1_code(code) do
    raise """
    Expected a subnational2 region code, but got: #{inspect(code)}
    """
  end
end
