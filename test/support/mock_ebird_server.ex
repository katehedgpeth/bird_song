defmodule BirdSong.MockEbirdServer do
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

    Bypass.expect(bypass, &success_response/1)

    :ok
  end

  defp success_response(
         %Plug.Conn{path_info: ["v2", "ref", "region", "list", subnational, country]} = conn
       ) do
    do_success_response(conn, :Regions, {
      :regions,
      level: String.to_existing_atom(subnational), parent: country
    })
  end

  defp success_response(%Conn{path_info: ["v2", "data", "obs", _region, "recent"]} = conn) do
    Conn.resp(conn, 200, File.read!("test/mock_data/recent_observations.json"))
  end

  defp do_success_response(%Conn{} = conn, worker_atom, request) do
    %Services{ebird: %Ebird{} = ebird} = Services.all()

    worker = Map.fetch!(ebird, worker_atom)

    case DataFile.read(%DataFile.Data{
           worker: worker,
           request: request
         }) do
      {:error, error} ->
        raise error

      # Plug.Conn.resp(conn, 501, Jason.encode!(%{error: inspect(error)}))

      {:ok, file} ->
        Plug.Conn.resp(conn, 200, file)
    end
  end
end
