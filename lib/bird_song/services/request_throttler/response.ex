defmodule BirdSong.Services.RequestThrottler.Response do
  alias BirdSong.Services.Helpers
  @enforce_keys [:base_url, :response, :timers, :request]
  defstruct [:base_url, :response, :timers, :request]

  @type jason_primitive() :: String.t() | integer() | boolean()
  @type jason_map() :: %{String.t() => any()}
  @type jason_list() :: [jason_map() | jason_primitive()]

  @type t() :: %__MODULE__{
          base_url: String.t(),
          response: Helpers.api_response(),
          timers: BirdSong.Services.RequestThrottler.timers(),
          request: HTTPoison.Request.t()
        }
end
