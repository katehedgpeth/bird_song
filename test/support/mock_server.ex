defmodule BirdSong.MockServer do
  require Logger
  use BirdSong.MockDataAttributes

  alias Plug.Conn

  alias BirdSong.{
    Bird,
    Services,
    Services.DataFile,
    Services.Service
  }

  @ebird_token :bird_song
               |> Application.compile_env(BirdSong.Services.Ebird)
               |> Keyword.fetch!(:token)

  def success_response(
        %Conn{
          request_path: @xeno_canto_path,
          params: %{"query" => sci_name}
        } = conn
      ) do
    do_success_response(conn, Map.fetch!(%Services{}, :recordings), sci_name)
  end

  def success_response(
        %Conn{
          request_path: @flickr_path,
          params: %{"text" => sci_name}
        } = conn
      ) do
    do_success_response(conn, Map.fetch!(%Services{}, :images), sci_name)
  end

  def success_response(
        %Conn{
          path_info: ["v2", "data", "obs", _, "recent"],
          params: %{"back" => "30"},
          req_headers: headers
        } = conn
      ) do
    case Enum.into(headers, %{}) do
      %{"x-ebirdapitoken" => @ebird_token} ->
        Conn.resp(
          conn,
          200,
          "test/mock_data/recent_observations.json"
          |> Path.relative_to_cwd()
          |> File.read!()
        )

      %{} ->
        Logger.warn("""
        EBIRD TOKEN NOT FOUND IN HEADERS
        \t\texpected: [{"x-ebirdapitoken", #{inspect(@ebird_token)}}]
        \t\tgot: #{inspect(headers)}
        """)

        Conn.resp(conn, 403, "token not found in #{inspect(headers)}")
    end
  end

  def success_response(%Conn{req_headers: headers} = conn) when is_list(headers) do
    conn
    |> Map.replace!(:req_headers, Enum.into(headers, %{}))
    |> success_response()
  end

  defp do_success_response(%Conn{} = conn, %Service{} = service, "" <> sci_name) do
    {:ok, %Bird{} = bird} = Bird.get_by_sci_name(sci_name)
    service_response(conn, bird, service)
  end

  defp logged_not_found_response(conn, %{} = body) do
    body
    |> Enum.map(&(&1 |> Tuple.to_list() |> Enum.join("=")))
    |> Enum.join(" ")
    |> Logger.warn()

    not_found_response(conn, body)
  end

  def not_found_response(conn, body \\ %{error: "not_found"}) do
    Conn.resp(conn, 404, Jason.encode!(body))
  end

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  defp service_response(%Conn{} = conn, %Bird{} = bird, service) do
    %DataFile.Data{request: bird, service: service}
    |> DataFile.read()
    |> case do
      {:ok, "" <> body} ->
        Logger.debug(
          "[#{__MODULE__}] response_mocked=true service=#{service} bird=#{bird.common_name}"
        )

        Conn.resp(conn, 200, body)

      {:error, :enoent} ->
        logged_not_found_response(conn, %{
          error: :file_not_found,
          bird: bird.common_name,
          service: service.name
        })
    end
  end
end
