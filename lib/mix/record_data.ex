defmodule Mix.Tasks.BirdSong.Record do
  use Mix.Task

  @moduledoc "Fetch missing recordings and images"
  @shortdoc "Fetch missing recordings and images"

  @requirements ["app.config", "app.start"]

  def run(args) do
    BirdSong.Data.Recorder.record(args, BirdSong.Services.ensure_started())
  end
end
