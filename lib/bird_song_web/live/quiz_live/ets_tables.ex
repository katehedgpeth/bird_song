defmodule BirdSongWeb.QuizLive.EtsTables do
  use BirdSongWeb.QuizLive.Assign
  alias Phoenix.LiveView.Socket

  defstruct [:birds, :tasks]

  @type t() :: %__MODULE__{
          tasks: :ets.table()
        }

  defguard is_ets(maybe_ets) when is_reference(maybe_ets) or is_atom(maybe_ets)

  def assign_new_tables(%Socket{} = socket) do
    Phoenix.LiveView.assign_new(socket, :ets_tables, &new/0)
  end

  defp new() do
    %__MODULE__{
      tasks: :ets.new(__MODULE__.Tasks, [:public])
    }
  end
end
