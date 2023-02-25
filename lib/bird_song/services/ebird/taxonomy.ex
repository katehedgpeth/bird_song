defmodule BirdSong.Services.Ebird.Taxonomy do
  use GenServer
  alias BirdSong.Services.Ebird.Species

  defstruct [:ets_table]

  @file_path :bird_song
             |> Application.compile_env!(:ebird)
             |> Keyword.fetch!(:taxonomy_file)

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def lookup("" <> sci_name, server_name \\ __MODULE__) do
    GenServer.call(server_name, {:lookup, sci_name})
  end

  def state(server_name \\ __MODULE__) do
    GenServer.call(server_name, :state)
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link(options) do
    GenServer.start_link(
      __MODULE__,
      @file_path,
      name: Keyword.get(options, :name, __MODULE__)
    )
  end

  def init(file) do
    state = %__MODULE__{
      ets_table: :ets.new(__MODULE__, [])
    }

    file
    |> File.read!()
    |> Jason.decode!()
    |> Enum.each(&parse_and_save(&1, state.ets_table))

    {:ok, state}
  end

  def handle_call({:lookup, sci_name}, _from, %__MODULE__{} = state) do
    reply =
      case :ets.lookup(state.ets_table, sci_name) do
        [{^sci_name, %Species{} = species}] -> {:ok, species}
        [] -> :not_found
      end

    {:reply, reply, state}
  end

  def handle_call(:state, _from, %__MODULE__{} = state) do
    {:reply, state, state}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp parse_and_save(raw, ets_table) do
    species = Species.parse(raw)
    :ets.insert(ets_table, {species.sci_name, species})
  end
end
