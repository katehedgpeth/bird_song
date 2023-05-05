defmodule BirdSong.Services.Ebird.RegionETS do
  use BirdSong.Services.Worker, option_keys: [:seed_folder]

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Region,
    Services.Worker
  }

  @enforce_keys [:ets, :worker]
  defstruct [:ets, :worker, seed_folder: :not_set]

  @type t() :: %__MODULE__{
          ets: :ets.table(),
          seed_folder: String.t() | :not_set,
          worker: Worker.t()
        }

  @type search_result() :: {:ok, %Region{}} | {:error, :not_found}

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def get("" <> code, %Worker{instance_name: name}) do
    GenServer.call(name, {:get, code})
  end

  def get!("" <> code, %Worker{} = worker) do
    case get(code, worker) do
      {:ok, region} -> region
      {:error, error} -> raise error
    end
  end

  def save(%Region{} = region, %Worker{instance_name: name}) do
    GenServer.cast(name, {:save, region})
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  @impl Worker
  def do_init(opts) do
    {:ok, build_state(opts), {:continue, :seed}}
  end

  @impl GenServer
  def handle_call({:get, code}, _from, %__MODULE__{} = state) do
    {:reply, get_from_ets(state, code), state}
  end

  @impl GenServer
  def handle_cast({:save, %Region{} = region}, %__MODULE__{} = state) do
    true = do_save(state, region)
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:set_seed_folder, %__MODULE__{} = state) do
    {:noreply, set_seed_folder(state), {:continue, :seed}}
  end

  def handle_continue(:seed, %__MODULE__{seed_folder: :not_set} = state) do
    {:noreply, state, {:continue, :set_seed_folder}}
  end

  def handle_continue(:seed, %__MODULE__{seed_folder: "" <> _} = state) do
    :ok = seed_cache(state)
    {:noreply, state}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  defp build_state(opts) do
    opts
    |> Keyword.put_new(:seed_folder, :not_set)
    |> Keyword.put_new_lazy(:ets, fn -> :ets.new(__MODULE__, []) end)
    |> __struct__()
  end

  @spec set_seed_folder(t()) :: t()
  defp set_seed_folder(%__MODULE__{} = state) do
    {:ok, path} =
      :Regions
      |> Ebird.get_instance_child()
      |> Worker.full_data_folder_path()

    %{state | seed_folder: path}
  end

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
