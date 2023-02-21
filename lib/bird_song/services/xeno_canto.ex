defmodule BirdSong.Services.XenoCanto do
  alias __MODULE__.Cache

  def url(query) do
    :bird_song
    |> Application.get_env(:xeno_canto)
    |> Keyword.fetch!(:base_url)
    |> List.wrap()
    |> Enum.concat(["api", "2", "recordings?query=" <> format_query(query)])
    |> Path.join()
  end

  def get_recording(bird) do
    Cache.get(bird)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
