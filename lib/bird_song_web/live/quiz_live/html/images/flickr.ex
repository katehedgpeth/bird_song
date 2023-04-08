defmodule BirdSongWeb.QuizLive.HTML.Images.Flickr do
  alias BirdSong.Services.Flickr.Photo

  @behaviour BirdSongWeb.QuizLive.HTML.Image

  def src(%Photo{url: url}), do: url
end
