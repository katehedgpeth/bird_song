defmodule BirdSongWeb.QuizLive.EtsTables do
  alias Phoenix.LiveView.Socket

  defstruct [:birds, :tasks]

  @type t() :: %__MODULE__{
          birds: :ets.table(),
          tasks: :ets.table()
        }

  defguard is_ets(maybe_ets) when is_reference(maybe_ets) or is_atom(maybe_ets)

  def assign_new(%Socket{} = socket) do
    Phoenix.LiveView.assign_new(socket, :ets_tables, &new/0)
  end

  defp new() do
    %__MODULE__{
      birds: :ets.new(__MODULE__.Birds, []),
      tasks: :ets.new(__MODULE__.Tasks, [])
    }
  end
end
