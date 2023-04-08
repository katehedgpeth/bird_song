defmodule BirdSong.Services.Ebird do
  alias __MODULE__.{
    Observations,
    Regions,
    RegionSpeciesCodes
  }

  @base_url "https://api.ebird.org"

  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  @type request_data() ::
          Observations.request_data()
          | Regions.request_data()
          | RegionSpeciesCodes.request_data()

  def base_url(), do: @base_url

  def token_header() do
    {"x-ebirdapitoken", @token}
  end
end
