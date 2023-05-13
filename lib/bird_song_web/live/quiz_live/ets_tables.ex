defmodule BirdSongWeb.QuizLive.EtsTables do
  use BirdSong.GenServer, name: __MODULE__, keep_name_opt?: true

  defstruct [:birds, :assigns]

  @type t() :: %__MODULE__{
          assigns: :ets.table()
        }

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec get_tables() :: t()
  def get_tables() do
    GenServer.call(__MODULE__, :get_tables)
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def handle_call(:get_tables, _from, %__MODULE__{} = state) do
    {:reply, state, state}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec build_state(Keyword.t()) :: t()
  defp build_state(opts) do
    {name, opts} = Keyword.pop!(opts, :name)

    opts
    |> Keyword.put_new_lazy(:assigns, fn ->
      name
      |> Module.concat(Assigns)
      |> :ets.new([:public])
    end)
    |> __struct__()
  end
end
