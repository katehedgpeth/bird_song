defmodule BirdSong.Data.Scraper do
  @type response :: {:ok, [Map.t()]} | {:error, BadResponseError} | {:error, TimeoutError}

  @callback run(GenServer.server(), any()) :: response()
end
