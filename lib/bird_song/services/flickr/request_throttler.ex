defmodule BirdSong.Services.Flickr.RequestThrottler do
  use BirdSong.Services.RequestThrottler

  @impl BirdSong.Services.RequestThrottler
  defdelegate call_endpoint(request, state), to: RequestThrottler
end
