defmodule BirdSong.Services.Ebird.Recordings.BadResponseError do
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

defmodule BirdSong.Services.Ebird.Recordings.TimeoutError do
  defexception [:js_message]

  def message(%__MODULE__{js_message: message}) do
    """
    Received unexpected message from port:
    #{inspect(message)}
    """
  end
end

defmodule BirdSong.Services.Ebird.Recordings.JsonParseError do
  defexception [:js_message, :input]

  def message(%__MODULE__{js_message: js_message, input: input}) do
    """
    Error parsing JSON in playwright runner:
    message: #{inspect(js_message)}
    input: #{inspect(input)}
    """
  end
end

defmodule BirdSong.Services.Ebird.Recordings.UnknownMessageError do
  defexception [:data]

  def message(%__MODULE__{data: data}) do
    """
    Received unexpected message from port:
    #{inspect(data)}
    """
  end
end
