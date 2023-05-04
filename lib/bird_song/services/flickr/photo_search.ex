defmodule BirdSong.Services.Flickr.PhotoSearch.Response do
  defdelegate parse(response, args), to: BirdSong.Services.Flickr.Response
end

defmodule BirdSong.Services.Flickr.PhotoSearch do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :flickr_photo_search

  alias BirdSong.{
    Bird,
    Services.Flickr,
    Services.ThrottledCache
  }

  @base_query Map.merge(
                Flickr.base_query(),
                %{
                  method: "flickr.photos.search"
                }
              )

  def get_images(%Bird{} = bird, %Worker{} = worker) do
    get(bird, worker)
  end

  #########################################################
  #########################################################
  ##
  ##  CALLBACKS
  ##
  #########################################################

  @impl ThrottledCache
  def endpoint(%Bird{}) do
    Path.join(["services", "rest"])
  end

  @impl ThrottledCache
  # do not send user agent headers to Flickr
  def headers(%Bird{}), do: []

  @impl ThrottledCache
  def params(%Bird{sci_name: sci_name}) do
    Map.put(@base_query, :text, sci_name)
  end

  @impl ThrottledCache
  def response_module() do
    Flickr.Response
  end
end
