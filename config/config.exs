# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

one_second = 1_000

env =
  Map.new(
    [
      "BIRD_SONG_ADMIN_EMAIL",
      "BIRD_SONG_SIGNING_SALT",
      "EBIRD_API_TOKEN",
      "FLICKR_API_KEY",
      "CHIRPITY_DOMAIN"
    ],
    fn name ->
      case System.get_env(name) do
        "" <> val ->
          {
            name
            |> String.downcase()
            |> String.to_existing_atom(),
            val
          }

        _ ->
          raise BirdSong.MissingEnvironmentVariableError.exception(name: name)
      end
    end
  )

config :bird_song,
  ecto_repos: [BirdSong.Repo]

# Configures the endpoint
config :bird_song, BirdSongWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: BirdSongWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: BirdSong.PubSub,
  live_view: [
    signing_salt: env.bird_song_signing_salt
  ],
  site_encrypt: [
    domain: env.chirpity_domain,
    email: env.bird_song_admin_email
  ]

config :bird_song, BirdSong.Accounts.Mailer, adapter: Swoosh.Adapters.Local

config :bird_song, BirdSong.Services.ThrottledCache,
  backlog_timeout_ms: :infinity,
  throttle_ms: 1 * one_second,
  admin_email: env.bird_song_admin_email

config :bird_song, BirdSong.Services.Ebird,
  token: env.ebird_api_token,
  taxonomy_file: Path.relative_to_cwd("data/taxonomy.json")

config :bird_song, BirdSong.Services.MacaulayLibrary,
  base_url: "https://search.macaulaylibrary.org"

config :bird_song, BirdSong.Services.MacaulayLibrary.Playwright, default_timeout: 3_000

config :bird_song, BirdSong.Services.XenoCanto, write_to_disk?: false

config :bird_song, BirdSong.Services.Flickr,
  write_to_disk?: false,
  api_key: env.flickr_api_key

config :bird_song, BirdSong.Services,
  images: BirdSong.Services.Flickr,
  recordings: BirdSong.Services.XenoCanto,
  observations: BirdSong.Services.Ebird.Observations

config :bird_song, BirdSong.Data.Recorder, stream_timeout_ms: :infinity

config :bird_song, BirdSong.Accounts.Guardian, issuer: "bird_song"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.14.29",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ],
  playwright_runner: [
    args:
      ~w(js/playwright_runner.js --bundle --outdir=../priv/static/assets --platform=node --log-level=error),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
    --config=tailwind.config.js
    --input=css/app.css
    --output=../priv/static/assets/app.css
  ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
