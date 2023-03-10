defmodule BirdSong.Services.Service do
  defstruct [:name, :whereis, :response, :exit_reason]

  @type t() :: %__MODULE__{
          name: atom(),
          whereis: GenServer.name(),
          response: struct() | nil,
          exit_reason: atom()
        }
end
