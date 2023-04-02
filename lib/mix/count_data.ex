defmodule Mix.Tasks.BirdSong.CountData do
  use Mix.Task

  @shortdoc "Print a count of how many birds are in the DB, and how many have images and recordings."

  @requirements ["app.config", "app.start"]

  def run([]) do
    BirdSong.Services.ensure_started()
    |> BirdSong.Data.Counts.get()
    |> Map.from_struct()
    |> Enum.map(&print/1)
  end

  def print({:data_folder_bytes = key, val}) do
    IO.inspect("#{val / 1000} KB", label: key)
    {key, val}
  end

  def print({key, val}) do
    IO.inspect(val, label: key)
    {key, val}
  end
end
