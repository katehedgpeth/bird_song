defmodule BirdSong.MockServer do
  require Logger
  use BirdSong.MockDataAttributes

  alias BirdSong.Services.Helpers
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
    do_success_response(conn, :recordings, sci_name)
  end

  def success_response(
        %Conn{
          request_path: @flickr_path,
          params: %{"text" => sci_name}
        } = conn
      ) do
    do_success_response(conn, :images, sci_name)
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

  defp do_success_response(%Conn{} = conn, service_type, "" <> sci_name)
       when service_type in [:images, :recordings] do
    {:ok, %Bird{} = bird} = Bird.get_by_sci_name(sci_name)

    service_response(
      conn,
      bird,
      %Services{}
      |> Map.fetch!(service_type)
      |> Service.ensure_started()
    )
  end

  defp logged_not_found_response(conn, %{} = body) do
    Helpers.log(body, __MODULE__)

    not_found_response(conn, body)
  end

  def not_found_response(conn, body \\ %{error: "not_found"}) do
    Conn.resp(conn, 404, Jason.encode!(body))
  end

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  defp service_response(%Conn{} = conn, %Bird{} = bird, %Service{} = service) do
    %DataFile.Data{request: bird, service: service}
    |> DataFile.read()
    |> case do
      {:ok, "" <> body} ->
        Helpers.log(
          %{
            response_mocked: true,
            service: service.module,
            bird: bird.common_name
          },
          __MODULE__
        )

        Conn.resp(conn, 200, body)

      {:error, {:enoent, path}} ->
        logged_not_found_response(conn, %{
          error: :file_not_found,
          bird: bird.common_name,
          service: service.module,
          path: path
        })
    end
  end
end
