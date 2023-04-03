defmodule BirdSong.Data.Scraper.BadResponseError do
  defexception [:response_body, :status, :url]

  def message(%__MODULE__{response_body: response_body, status: status, url: url}) do
    """
    Received bad response from API:
    status: #{status}
    url: #{inspect(url)}
    response_body: #{inspect(response_body)}
    """
  end
end

defmodule BirdSong.Data.Scraper.TimeoutError do
  defexception [:module, :timeout_message]

  def message(%__MODULE__{module: module, timeout_message: message}) do
    """
    #{inspect(module)} process timed out.
    #{inspect(message)}
    """
  end
end

defmodule BirdSong.Data.Scraper.JsonParseError do
  defexception [:error_message, :input]

  def message(%__MODULE__{error_message: error_message, input: input}) do
    """
    Error parsing JSON in playwright runner:
    message: #{inspect(error_message)}
    input: #{inspect(input)}
    """
  end
end

defmodule BirdSong.Data.Scraper.UnknownMessageError do
  defexception [:data]

  def message(%__MODULE__{data: data}) do
    """
    Received unexpected message from port:
    #{inspect(data)}
    """
  end
end
