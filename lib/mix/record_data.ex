defmodule Mix.Tasks.BirdSong.RecordData do
  use Mix.Task

  @moduledoc "Fetch missing recordings and images"
  @shortdoc "Fetch missing recordings and images"

  @requirements ["app.config", "app.start"]

  def run(args, services \\ BirdSong.Services.ensure_started()) do
    BirdSong.Data.Recorder.record(args, services)
  end
end
