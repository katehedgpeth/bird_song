defmodule BirdSong.Services.XenoCanto do
  alias __MODULE__.Cache
  alias BirdSong.Bird
  alias BirdSong.Services.Helpers

  def url(query) do
    :xeno_canto
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["api", "2", "recordings?query=" <> format_query(query)])
    |> Path.join()
  end

  def get_recordings(%Bird{} = bird, server) when is_pid(server) or is_atom(server) do
    Cache.get(bird, server)
  end

  def has_data?(%Bird{} = bird, server) when is_pid(server) or is_atom(server) do
    Cache.has_data?(bird, server)
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
