defmodule BirdSong.Services.Ebird.Regions.RegionETS do
  alias BirdSong.Services.Ebird.Regions.Region
  use GenServer

  @enforce_keys [:ets, :seed_folder]
  defstruct [:ets, :seed_folder]

  @type t() :: %__MODULE__{
          ets: :ets.table(),
          seed_folder: String.t()
        }

  @type search_result() :: {:ok, %Region{}} | {:error, :not_found}

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def get("" <> code, server \\ __MODULE__) do
    GenServer.call(server, {:get, code})
  end

  def save(%Region{} = region, server \\ __MODULE__) do
    GenServer.cast(server, {:save, region})
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link([]) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(opts) do
    send(self(), :seed)

    {:ok,
     %__MODULE__{
       ets: :ets.new(__MODULE__, []),
       seed_folder: Keyword.get(opts, :seed_folder, "data/regions")
     }}
  end

  def handle_call({:get, code}, _from, %__MODULE__{} = state) do
    {:reply, get_from_ets(state, code), state}
  end

  def handle_cast({:save, %Region{} = region}, %__MODULE__{} = state) do
    true = do_save(state, region)
    {:noreply, state}
  end

  def handle_info(:seed, %__MODULE__{} = state) do
    seed_cache(state)

    {:noreply, state}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp do_save(%__MODULE__{ets: ets}, %Region{code: code} = region) do
    :ets.insert(ets, {code, region})
  end

  defp get_from_ets(%__MODULE__{ets: ets}, "" <> code) do
    case :ets.lookup(ets, code) do
      [{^code, %Region{} = region}] -> {:ok, region}
      [] -> {:error, :not_found}
    end
  end

  defp read_file(%__MODULE__{seed_folder: seed_folder}, "" <> file_name) do
    seed_folder
    |> Path.join(file_name <> ".json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp seed_cache(%__MODULE__{} = state) do
    state
    |> read_file("all-countries")
    |> Enum.map(&Region.parse!/1)
    |> Enum.each(&seed_country(state, &1))
  end

  defp seed_country(%__MODULE__{} = state, %Region{level: :country} = country) do
    do_save(state, country)

    seed_subregions(state, country, :subnational1)
    seed_subregions(state, country, :subnational2)
  end

  defp seed_subregions(
         %__MODULE__{} = state,
         %Region{level: :country, code: code},
         level
       ) do
    state
    |> read_file(code <> "-" <> Atom.to_string(level))
    |> Enum.map(&Region.parse!/1)
    |> Enum.each(&do_save(state, &1))
  end
end
