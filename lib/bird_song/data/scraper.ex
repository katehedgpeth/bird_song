defmodule BirdSong.Data.Scraper do
  @type error() ::
          __MODULE__.BadResponseError
          | __MODULE__.TimeoutError
          | __MODULE__.ConnectionError
          | __MODULE__.JsonParseError
          | __MODULE__.UnknownMessageError
  @type response :: {:ok, [Map.t()]} | {:error, error()}

  @callback run(
              BirdSong.Services.Supervisor.service_instance_name(),
              any(),
              integer()
            ) ::
              response()
end
