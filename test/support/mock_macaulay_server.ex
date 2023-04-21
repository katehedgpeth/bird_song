defmodule BirdSong.MockMacaulayServer do
  alias Plug.Conn

  @ebird_login_html File.read!("test/mock_data/ebird_login.html")
  @ebird_list_html File.read!("test/mock_data/ebird_recordings.html")
  @ebird_recordings_json File.read!("test/mock_data/ebird_recordings.json")
  @ebird_username System.get_env("EBIRD_USERNAME")
  @ebird_password System.get_env("EBIRD_PASSWORD")

  def setup(%{bypass: %Bypass{} = bypass} = tags) do
    recordings_response = Map.get(tags, :recordings_response, &ebird_recordings_get/1)
    list_html_response = Map.get(tags, :list_html_response, &ebird_list_get/1)
    expect_api_call? = Map.get(tags, :expect_api_call?, true)
    expect_login? = Map.get(tags, :expect_login?, true)

    Bypass.expect(bypass, "GET", "/catalog", list_html_response)

    if expect_api_call? do
      Bypass.expect(bypass, "GET", "/api/v2/search", recordings_response)
    end

    if expect_login? do
      Bypass.expect(bypass, "GET", "/cassso/login", &ebird_login_get/1)
      Bypass.expect(bypass, "POST", "/cassso/login", &ebird_login_post/1)
      Bypass.expect(bypass, &asset_response/1)
    end
  end

  def asset_response(%Conn{path_info: ["gtm.js"]} = conn) do
    do_asset_response(conn)
  end

  def asset_response(%Conn{path_info: ["api", "v1", "asset" | _]} = conn) do
    do_asset_response(conn)
  end

  def asset_response(%Conn{path_info: ["_nuxt" | _]} = conn) do
    do_asset_response(conn)
  end

  defp do_asset_response(conn) do
    Conn.resp(conn, 200, ~s({"mocked_data": true}))
  end

  defp ebird_list_get(conn) do
    Conn.resp(conn, 200, @ebird_list_html)
  end

  defp ebird_login_get(conn) do
    Conn.resp(conn, 200, @ebird_login_html)
  end

  defp ebird_login_post(%Conn{} = conn) do
    {:ok, param_string, conn} = Conn.read_body(conn)

    param_string
    |> URI.query_decoder()
    |> Enum.into(%{})
    |> case do
      %{"username" => @ebird_username, "password" => @ebird_password} ->
        conn
        |> Conn.put_resp_header("location", "/catalog?view=list")
        |> Conn.resp(302, "You are being redirected")

      %{} ->
        Conn.resp(conn, 200, @ebird_login_html)
    end
  end

  defp ebird_recordings_get(%Conn{} = conn) do
    Conn.resp(conn, 200, @ebird_recordings_json)
  end

  def not_found_response(conn) do
    Plug.Conn.resp(conn, 404, "That page does not exist")
  end

  def not_authorized_response(conn) do
    Plug.Conn.resp(conn, 403, ~s({"error": "You are not authorized to perform this action"}))
  end

  def bad_structure_response(conn) do
    Plug.Conn.resp(conn, 200, "<div>This is an unexpected document structure</div>")
  end
end
