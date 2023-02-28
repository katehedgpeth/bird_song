defmodule BirdSong.Services.Flickr do
  use BirdSong.Services.ThrottledCache, ets_opts: [], ets_name: :flickr_cache

  alias BirdSong.{
    Bird,
    Services.Helpers,
    Services.Flickr.Response
  }

  @api_key :bird_song
           |> Application.compile_env(:flickr)
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

  def get_from_api(%Bird{} = bird) do
    bird
    |> url()
    |> HTTPoison.get()
    |> Helpers.parse_api_response()
    |> case do
      {:ok, response} -> {:ok, Response.parse(response)}
      error -> error
    end
  end

  def mock_file_name(%Bird{common_name: name}), do: "flickr_" <> name

  def url(%Bird{} = bird) do
    :flickr
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
