defmodule BirdSongWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :bird_song
  use SiteEncrypt.Phoenix

  @site_encrypt :bird_song
                |> Application.compile_env(BirdSongWeb.Endpoint)
                |> Keyword.fetch!(:site_encrypt)
                |> Map.new()

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_bird_song_key",
    signing_salt: "d7bPRpjl"
  ]

  @impl Phoenix.Endpoint
  def init(_key, config) do
    {:ok, SiteEncrypt.Phoenix.configure_https(config)}
  end

  @impl SiteEncrypt
  def certification do
    SiteEncrypt.configure(
      client: :native,
      domains: [@site_encrypt.domain, "www." <> @site_encrypt.domain],
      emails: [@site_encrypt.email],
      db_folder: Application.get_env(:bird_song, :cert_path, "tmp/site_encrypt_db"),
      directory_url:
        case Application.get_env(:bird_song, :cert_mode, "local") do
          "local" -> {:internal, port: 4002}
          "staging" -> "https://acme-staging-v02.api.letsencrypt.org/directory"
          "production" -> "https://acme-v02.api.letsencrypt.org/directory"
        end
    )
  end

  def www_redirect(%Plug.Conn{} = conn, _options) do
    if String.starts_with?(conn.host, "www." <> host()) do
      conn
      |> Phoenix.Controller.redirect(external: "https://" <> host())
      |> halt()
    else
      conn
    end
  end

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # redirect all www. requests to the root url
  plug :www_redirect

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :bird_song,
    gzip: false,
    only: ~w(assets fonts images favicon.ico robots.txt)

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :bird_song
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug BirdSongWeb.Router
end
