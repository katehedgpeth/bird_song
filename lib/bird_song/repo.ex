defmodule BirdSong.Repo do
  use Ecto.Repo,
    otp_app: :bird_song,
    adapter: Ecto.Adapters.Postgres
end
