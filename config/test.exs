import Config

one_second = 1_000

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :bird_song, BirdSong.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "bird_song_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :bird_song, BirdSongWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hrIR1FkwdDB5LojQi0KtqNAcO+AysoHdghdJX1o+zWn5i75h2r70T8X2tlo9RqeP",
  server: false

config :bird_song, :xeno_canto,
  throttle_ms: 1,
  backlog_timeout_ms: 5 * one_second,
  api_response_timeout_ms: one_second

# Print only warnings and errors during test
config :logger, level: :warn

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
