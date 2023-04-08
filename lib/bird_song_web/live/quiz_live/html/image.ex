defmodule BirdSongWeb.QuizLive.HTML.Image do
  @type image() :: BirdSong.Services.Flickr.Photo.t()

  @callback src(image()) :: String.t()
end
