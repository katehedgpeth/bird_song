defmodule BirdSong.Services.XenoCanto do
  alias __MODULE__.Cache
  alias BirdSong.Services.Helpers

  def url(query) do
    :xeno_canto
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["api", "2", "recordings?query=" <> format_query(query)])
    |> Path.join()
  end

  def get_recording(bird, server) do
    Cache.get(bird, server)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
