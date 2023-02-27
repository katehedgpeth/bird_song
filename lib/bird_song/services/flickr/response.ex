defmodule BirdSong.Services.Flickr.Response do
  alias BirdSong.Services.Flickr.Photo

  defstruct [:num_pages, :page, :per_page, :total, photos: []]

  def parse(%{
        "photos" => %{
          "page" => page,
          "pages" => num_pages,
          "perpage" => per_page,
          "total" => total,
          "photo" => photos
        }
      }) do
    %__MODULE__{
      page: page,
      num_pages: num_pages,
      per_page: per_page,
      total: total,
      photos: Enum.map(photos, &Photo.parse/1)
    }
  end
end
