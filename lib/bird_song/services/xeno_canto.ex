defmodule BirdSong.Services.XenoCanto do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [:bag],
    ets_name: :xeno_canto

  alias __MODULE__.Response
  alias BirdSong.Bird
  alias BirdSong.Services.Helpers

  def url(%Bird{sci_name: sci_name}) do
    __MODULE__
    |> Helpers.get_env(:base_url)
    |> List.wrap()
    |> Enum.concat(["api", "2", "recordings?query=" <> format_query(sci_name)])
    |> Path.join()
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
