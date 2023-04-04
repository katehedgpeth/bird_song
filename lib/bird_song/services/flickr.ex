defmodule BirdSong.Services.Flickr do
  use BirdSong.Services.ThrottledCache,
    base_url: "https://www.flickr.com",
    data_folder_path: "data/images/flickr",
    ets_opts: [],
    ets_name: :flickr_cache

  alias BirdSong.{
    Bird,
    Services.Flickr.Response
  }

  @api_key :bird_song
           |> Application.compile_env(__MODULE__)
           |> Keyword.fetch!(:api_key)

  @query %{
    method: "flickr.photos.search",
    format: :json,
    nojsoncallback: 1,
    api_key: @api_key
  }

  def get_images(%Bird{} = bird, server) when is_pid(server) or is_atom(server) do
    get(bird, server)
  end

  def endpoint(%Bird{}) do
    Path.join(["services", "rest"])
  end

  def headers(%Bird{}), do: []

  def params(%Bird{sci_name: sci_name}) do
    Map.put(@query, :text, sci_name)
  end
end
