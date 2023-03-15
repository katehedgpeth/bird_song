defmodule BirdSong.Services.Service do
  alias BirdSong.Services.{Ebird, Flickr, XenoCanto}

  defstruct [:name, :whereis, :response, :exit_reason]

  @type t() :: %__MODULE__{
          name: atom(),
          whereis: GenServer.server(),
          response: Helpers.api_response() | nil,
          exit_reason: atom() | nil
        }

  @type response() :: XenoCanto.Response.t() | Flickr.Response.t() | Ebird.Response.t()
end
