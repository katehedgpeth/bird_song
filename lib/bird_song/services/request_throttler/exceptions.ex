defmodule BirdSong.Services.RequestThrottler.UrlError do
  defexception [:url]

  def message(%__MODULE__{url: url}) do
    """
    Expected url to be a path starting with "/", but got: #{url}
    """
  end
end

defmodule BirdSong.Services.RequestThrottler.NotStartedError do
  defexception [:name]

  def message(%__MODULE__{name: name}) do
    """
    RequestThrottler named #{name} is not started
    """
  end
end
