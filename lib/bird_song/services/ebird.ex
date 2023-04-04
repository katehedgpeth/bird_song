defmodule BirdSong.Services.Ebird do
  @base_url "https://api.ebird.org"

  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  def base_url(), do: @base_url

  def token_header() do
    {"x-ebirdapitoken", @token}
  end
end
