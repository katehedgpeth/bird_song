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
    Services,
    Services.DataFile,
    Services.Ebird
  }

  def setup(tags) do
    bypass =
      tags
      |> Map.fetch!(:bypasses)
      |> Map.fetch!(Ebird)
      |> Map.fetch!(:bypass)

    Bypass.expect(bypass, &response/1)

    :ok
  end

  # Ebird.Regions
  def response(
        %Plug.Conn{
          path_info: ["v2", "ref", "region", "list", subnational, country]
        } = conn
      ) do
    send_real_data(
      {:regions, level: String.to_existing_atom(subnational), parent: country},
      :Regions,
      conn
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

  @spec read_real_data(atom(), Ebird.request_data()) :: DataFile.read_response()
  defp read_real_data(worker_atom, request) do
    %Services{ebird: %Ebird{} = ebird} = Services.all()

    worker = Map.fetch!(ebird, worker_atom)

    DataFile.read(%DataFile.Data{
      worker: worker,
      request: request
    })
  end

  @spec respond({:ok, String.t()} | {:error, File.posix()}, Conn.t()) :: Conn.t()
  defp respond({:ok, body}, conn) do
    Conn.resp(conn, 200, body)
  end

  defp respond({:error, {:not_found, "" <> path}}, %Conn{} = conn) do
    Conn.resp(conn, 404, Jason.encode!(%{error: :not_found, path: path}))
  end

  defp respond!({:ok, body}, conn), do: respond({:ok, body}, conn)

  defp respond!({:error, error}, %Conn{}), do: raise(error)

  @spec send_mock_data!(String.t(), Conn.t()) :: Conn.t() | no_return()
  defp send_mock_data!(file_without_extension, conn) do
    file_without_extension
    |> read_mock_data()
    |> respond!(conn)
  end

  defp send_real_data(request, worker_atom, %Conn{} = conn) do
    worker_atom
    |> read_real_data(request)
    |> respond(conn)
  end
end
