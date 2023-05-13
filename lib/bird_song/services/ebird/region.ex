defmodule BirdSong.Services.Ebird.Region do
  alias BirdSong.Services.Ebird.RegionInfo

  alias __MODULE__.{
    MalformedRegionCodeError
  }

  defstruct [:code, :level, name: :unknown, info: :unknown]

  @type level() :: :country | :subnational1 | :subnational2

  @type t() :: %__MODULE__{
          code: String.t(),
          info: RegionInfo.t() | :unknown,
          name: String.t() | :unknown,
          level: level()
        }

  @sublevels %{
    country: :subnational1,
    subnational1: :subnational2
  }

  defguard is_region_level(level) when level in [:country, :subnational1, :subnational2]
  defguard is_child_level(level) when level in [:subnational1, :subnational2]
  defguard is_parent_level(level) when level in [:country, :subnational1]

  @spec get_parent(BirdSong.Services.Ebird.Region.t()) :: BirdSong.Region.t()
  def get_parent(%__MODULE__{} = region) do
    get_parent(region, :country)
  end

  @spec get_parent(BirdSong.Services.Ebird.Region.t(), level()) ::
          BirdSong.Region.t()
  def get_parent(%__MODULE__{level: :country}, _parent_level) do
    {:error, :no_parent}
  end

  def get_parent(%__MODULE__{level: child_level} = region, :country)
      when is_child_level(child_level) do
    region
    |> parse_country_code()
    |> BirdSong.Region.from_code!()
  end

  def get_parent(%__MODULE__{level: :subnational2, code: code}, :subnational1) do
    code
    |> parse_subnational1_code()
    |> BirdSong.Region.from_code!()
  end

  @spec get_parent!(BirdSong.Services.Ebird.Region.t()) ::
          BirdSong.Services.Ebird.Region.t()

  def get_parent!(%__MODULE__{} = region, level \\ :country) do
    region
    |> get_parent(level)
    |> raise_if_error!()
  end

  defp raise_if_error!({:error, error}) do
    raise error
  end

  defp raise_if_error!({:ok, response}), do: response

  def parse(%{"code" => code, "name" => name}) do
    with {:ok, level} <- parse_level(code) do
      __struct__(code: code, name: name, level: level)
    end
  end

  def parse!(%{} = raw) do
    case parse(raw) do
      %__MODULE__{} = region -> region
      {:error, error} -> raise error
    end
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
