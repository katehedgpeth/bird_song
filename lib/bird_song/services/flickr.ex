defmodule BirdSong.Services.Flickr do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :flickr_cache

  alias BirdSong.{
    Bird,
    Services.Helpers,
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

  def url(%Bird{} = bird) do
    __MODULE__
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["services", "rest", "?" <> format_query(bird)])
    |> Path.join()
  end

  def format_query(%Bird{sci_name: sci_name}) do
    @query
    |> Map.put(:text, sci_name)
    |> URI.encode_query()
  end
end
