defmodule BirdSong.Services.XenoCanto.Recordings do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [:bag],
    ets_name: :xeno_canto

  alias __MODULE__.Response

  alias BirdSong.{
    Bird,
    Services.ThrottledCache,
    Services.XenoCanto
  }

  @impl ThrottledCache
  def endpoint(%Bird{}) do
    Path.join(["api", "2", "recordings"])
  end

  @impl ThrottledCache
  def params(%Bird{sci_name: sci_name}) do
    %{query: format_query(sci_name)}
  end

  @impl ThrottledCache
  def response_module() do
    XenoCanto.Response
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE
  ##
  #########################################################

  defp format_query(query), do: String.replace(query, " ", "+")
end
