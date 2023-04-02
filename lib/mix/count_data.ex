defmodule Mix.Tasks.BirdSong.CountData do
  use Mix.Task

  @shortdoc "Print a count of how many birds are in the DB, and how many have images and recordings."

  @requirements ["app.config", "app.start"]

  def run([]) do
    BirdSong.Services.ensure_started()
    |> BirdSong.Data.Counts.get()
  end
end
