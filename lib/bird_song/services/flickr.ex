defmodule BirdSong.Services.Flickr do
  use BirdSong.Services.Supervisor,
    caches: [:PhotoSearch],
    base_url: "https://www.flickr.com",
    use_data_folder?: true

  @api_key :bird_song
           |> Application.compile_env(__MODULE__)
           |> Keyword.fetch!(:api_key)

  @base_query %{
    format: :json,
    nojsoncallback: 1,
    api_key: @api_key
  }

  def api_key(), do: @api_key

  def base_query(), do: @base_query
end
