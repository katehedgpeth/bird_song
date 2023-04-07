defmodule BirdSong.Services.XenoCanto do
  use BirdSong.Services.ThrottledCache,
    base_url: "https://xeno-canto.org",
    data_folder_path: "data/recordings/xeno_canto",
    ets_opts: [:bag],
    ets_name: :xeno_canto

  alias __MODULE__.Response
  alias BirdSong.Bird

  def endpoint(%Bird{}) do
    Path.join(["api", "2", "recordings"])
  end

  def params(%Bird{sci_name: sci_name}) do
    %{query: format_query(sci_name)}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
