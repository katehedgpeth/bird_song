# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

one_second = 1_000

config :bird_song,
  ecto_repos: [BirdSong.Repo],
  admin_email:
    (case System.get_env("BIRD_SONG_ADMIN_EMAIL") do
       "" <> email -> email
       _ -> raise "missing environment variable: BIRD_SONG_ADMIN_EMAIL"
     end)

# Configures the endpoint
config :bird_song, BirdSongWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: BirdSongWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: BirdSong.PubSub,
  live_view: [
    signing_salt:
      case System.get_env("BIRD_SONG_SIGNING_SALT") do
        "" <> salt -> salt
        nil -> raise "missing environment variable: BIRD_SONG_SIGNING_SALT"
      end
  ]

config :bird_song, BirdSong.Services.ThrottledCache,
  backlog_timeout_ms: :infinity,
  throttle_ms: 2 * one_second

config :bird_song, BirdSong.Services.Ebird,
  token:
    (case System.get_env("EBIRD_API_TOKEN") do
       "" <> token -> token
       nil -> raise "missing environment variable: EBIRD_API_TOKEN"
     end),
  taxonomy_file: Path.relative_to_cwd("data/taxonomy.json")

config :bird_song, BirdSong.Services.RequestThrottlers.MacaulayLibrary,
  base_url: "https://search.macaulaylibrary.org"

config :bird_song, BirdSong.Services.Ebird.Recordings.Playwright, default_timeout: 3_000

config :bird_song, BirdSong.Services.XenoCanto, write_to_disk?: false

config :bird_song, BirdSong.Services.Flickr,
  write_to_disk?: false,
  api_key:
    (case System.get_env("FLICKR_API_KEY") do
       "" <> key -> key
       nil -> raise "missing environment variable: BIRD_SONG_SIGNING_SALT"
     end)

config :bird_song, BirdSong.Services,
  images: BirdSong.Services.Flickr,
  recordings: BirdSong.Services.Ebird.Recordings,
  observations: BirdSong.Services.Ebird.Observations,
  stream_timeout_ms: :infinity

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
