defmodule BirdSong.Services.RequestThrottler.ForbiddenExternalURLError do
  defexception [:opts]

  def message(%__MODULE__{opts: opts}) do
    """


    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!
    !!!  Attempted to call an external service when it is expressly forbidden.
    !!!  To allow external calls in tests, pass allow_external_calls?: true as
    !!!  an option when starting the service's RequestThrottler.
    !!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    opts: #{inspect(opts)}
    """
  end
end

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
