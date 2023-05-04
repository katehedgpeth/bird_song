defmodule BirdSong.MockServer do
  require Logger
  use BirdSong.MockDataAttributes

  alias BirdSong.Services.Helpers
  alias Plug.Conn

  alias BirdSong.{
    Bird,
    Services.Worker
  }

  @ebird_token :bird_song
               |> Application.compile_env(BirdSong.Services.Ebird)
               |> Keyword.fetch!(:token)

  # defguard is_ebird_observation_path(info) when match?(["v2", "data", "obs", _, "recent"], info)
  defguardp is_ebird_obs_3(info) when tl(info) === ["recent"]

  defguardp is_ebird_obs_2(info)
            when hd(info) === "obs" and info |> tl() |> is_ebird_obs_3()

  defguardp is_ebird_obs_1(info)
            when hd(info) === "data" and is_ebird_obs_2(tl(info))

  defguard is_ebird_observation_path(info)
           when hd(info) === "v2" and is_ebird_obs_1(tl(info))

  def success_response(
        %Conn{
          request_path: "/" <> @xeno_canto_path,
          params: %{"query" => sci_name}
        } = conn
      ) do
    do_success_response(conn, {XenoCanto, :Recordings}, String.replace(sci_name, "+", " "))
  end

  def success_response(
        %Conn{
          request_path: "/" <> @flickr_path,
          params: %{"text" => sci_name}
        } = conn
      ) do
    do_success_response(conn, {Flickr, :PhotoSearch}, sci_name)
  end

  def success_response(
        %Conn{
          path_info: ["v2", "product", "spplist", _]
        } = conn
      ) do
    Conn.resp(conn, 200, File.read!("test/mock_data/region_species_codes/US-NC-067.json"))
  end

  def success_response(
        %Conn{
          path_info: path_info,
          params: %{"back" => "30"},
          req_headers: headers
        } = conn
      )
      when is_ebird_observation_path(path_info) do
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

  def success_response(%Conn{path_info: ["api", "v1", "asset", _, "spectrogram_small"]} = conn) do
    Conn.resp(conn, 200, ~s({"mocked_data": true}))
  end

  def success_response(%Conn{req_headers: headers} = conn) when is_list(headers) do
    conn
    |> Map.replace!(:req_headers, Enum.into(headers, %{}))
    |> success_response()
  end

  defp do_success_response(%Conn{} = conn, worker_tuple, "" <> sci_name)
       when is_tuple(worker_tuple) do
    {:ok, %Bird{} = bird} = Bird.get_by_sci_name(sci_name)

    service_response(
      conn,
      bird,
      worker_tuple
    )
  end

  defp logged_not_found_response(conn, %{} = body) do
    Helpers.log(body, __MODULE__, :warning)

    not_found_response(conn, body)
  end

  def not_found_response(conn, body \\ %{error: "not_found"}) do
    Conn.resp(conn, 404, Jason.encode!(body))
  end

  def error_response(conn), do: Plug.Conn.resp(conn, 500, "there was an error")

  defp service_response(%Conn{} = conn, %Bird{} = bird, {service, worker_atom}) do
    worker = service.get_instance_child(service, worker_atom)

    case Worker.read_from_disk(worker, bird) do
      {:ok, "" <> body} ->
        Helpers.log(
          %{
            response_mocked: true,
            worker: worker.instance_name,
            bird: bird.common_name
          },
          __MODULE__
        )

        Conn.resp(conn, 200, body)

      {:error, {:enoent, path}} ->
        logged_not_found_response(conn, %{
          error: :file_not_found,
          bird: bird.common_name,
          worker: worker.instance_name,
          path: path
        })
    end
  end
end
