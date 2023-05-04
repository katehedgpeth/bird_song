defmodule BirdSong.Services.Ebird.RequestThrottler do
  use BirdSong.Services.RequestThrottler

  @impl RequestThrottler
  def call_endpoint(request, %__MODULE__{}) do
    HTTPoison.request(request)
  end
end
