defmodule BirdSong.Services.Flickr.Photo do
  defstruct [:id, :owner_id, :url, :title]

  def parse(%{
        "id" => id,
        "owner" => owner_id,
        "secret" => secret,
        "server" => server,
        "title" => title
      }) do
    %__MODULE__{
      id: id,
      owner_id: owner_id,
      title: title,
      url:
        Path.join([
          "https://live.staticflickr.com",
          server,
          id <> "_" <> secret <> ".jpg"
        ])
    }
  end
end
