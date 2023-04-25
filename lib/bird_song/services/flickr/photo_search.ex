defmodule BirdSong.Services.Flickr.PhotoSearch.Response do
  defdelegate parse(response, args), to: BirdSong.Services.Flickr.Response
end

defmodule BirdSong.Services.Flickr.PhotoSearch do
  use BirdSong.Services.ThrottledCache,
    data_folder_path: "data/images/flickr",
    ets_opts: [],
    ets_name: :flickr_cache,
    throttler: BirdSong.Services.RequestThrottler.Flickr

  alias BirdSong.{
    Bird,
    Services.Flickr
  }

  @base_query Map.merge(
                Flickr.base_query(),
                %{
                  method: "flickr.photos.search"
                }
              )

  def endpoint(%Bird{}) do
    Path.join(["services", "rest"])
  end

  def get_images(%Bird{} = bird, server) when is_pid(server) or is_atom(server) do
    get(bird, server)
  end

  # do not send user agent headers to Flickr
  def headers(%Bird{}), do: []

  def params(%Bird{sci_name: sci_name}) do
    Map.put(@base_query, :text, sci_name)
  end

  def response_module() do
    Flickr.Response
  end
end
