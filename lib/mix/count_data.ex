defmodule Mix.Tasks.BirdSong.CountData do
  use Mix.Task

  @shortdoc "Print a count of how many birds are in the DB, and how many have images and recordings."

  @requirements ["app.config", "app.start"]

  def run(args) do
    BirdSong.Services.ensure_started()
    |> BirdSong.Data.Counts.get(parse_args(args))
    |> Map.from_struct()
    |> Enum.map(&print/1)
  end

  defp parse_args([]) do
    %{}
  end

  defp parse_args(["--region=" <> region]) do
    %{region: region}
  end

  def print({:data_folder_bytes = key, val}) do
    {divisor, unit} =
      case val do
        mb when mb > 1_000_000 -> {1_000_000, "MB"}
        kb when kb > 1_000 -> {1_000, "KB"}
      end

    IO.inspect("#{val / divisor} #{unit}", label: key)
    {key, val}
  end

  def print({key, val}) do
    IO.inspect(val, label: key)
    {key, val}
  end
end
