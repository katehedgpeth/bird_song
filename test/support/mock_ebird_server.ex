defmodule BirdSong.MockEbirdServer.UnknownPathPattern do
  use BirdSong.CustomError, [:path_info]

  def message_text(%__MODULE__{path_info: path_info}) do
    """
    Unknown path pattern:
    #{inspect(path_info)}
    """
  end
end

defmodule BirdSong.MockEbirdServer do
  alias BirdSong.CustomError
  alias BirdSong.MockEbirdServer.UnknownPathPattern
  alias Plug.Conn

  alias BirdSong.{
    Services.Ebird
  }

  def setup(tags) do
    tags
    |> get_bypass()
    |> Bypass.expect(&response/1)

    :ok
  end

  def get_bypass(tags) do
    tags
    |> Map.fetch!(:bypasses)
    |> Map.fetch!(Ebird)
    |> Map.fetch!(:bypass)
  end

  # Ebird.Regions
  def response(
        %Plug.Conn{
          path_info: ["v2", "ref", "region", "list", level, country]
        } = conn
      ) do
    Plug.Conn.resp(
      conn,
      200,
      File.read!("test/mock_data/regions/ebird/#{country}-#{level}.json")
    )
  end

  # Ebird.Observations
  def response(%Conn{path_info: ["v2", "data", "obs", _region, "recent"]} = conn) do
    send_mock_data!("recent_observations", conn)
  end

  # Ebird.RegionSpeciesCodes
  def response(%Conn{path_info: ["v2", "product", "spplist", region]} = conn) do
    "region_species_codes"
    |> Path.join(region)
    |> send_mock_data!(conn)
  end

  def response(%Conn{path_info: path_info}) do
    raise UnknownPathPattern.exception(path_info: path_info)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec read_mock_data(String.t()) :: {:ok, String.t()} | {:error, File.posix()}
  defp read_mock_data(file_without_extension) do
    if String.ends_with?(file_without_extension, ".json") do
      raise ArgumentError.exception(
              message:
                CustomError.format_with_space(
                  "Do not add an extension to the file name passed to &MockEbirdServer.read_mock_data/2",
                  ArgumentError
                )
            )
    end

    "test/mock_data"
    |> Path.join(file_without_extension <> ".json")
    |> File.read()
  end

  @spec respond({:ok, String.t()} | {:error, File.posix()}, Conn.t()) :: Conn.t()
  defp respond({:ok, body}, conn) do
    Conn.resp(conn, 200, body)
  end

  defp respond!({:ok, body}, conn), do: respond({:ok, body}, conn)

  defp respond!({:error, error}, %Conn{}), do: raise(error)

  @spec send_mock_data!(String.t(), Conn.t()) :: Conn.t() | no_return()
  defp send_mock_data!(file_without_extension, conn) do
    file_without_extension
    |> read_mock_data()
    |> respond!(conn)
  end
end
