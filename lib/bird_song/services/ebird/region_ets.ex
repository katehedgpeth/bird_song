defmodule BirdSong.FileError do
  use BirdSong.CustomError, [:region]

  def message_text(%__MODULE__{region: region}) do
    """
    Cannot read RegionInfo file

    #{inspect(region)}
    """
  end
end

defmodule BirdSong.Services.Ebird.RegionETS do
  use BirdSong.Services.Worker, option_keys: [:seed_folders]

  alias BirdSong.{
    Services.Ebird,
    Services.Ebird.Region,
    Services.Ebird.RegionInfo,
    Services.Worker
  }

  @enforce_keys [:ets, :worker]
  defstruct [:ets, :worker, seed_folders: :not_set]

  @type t() :: %__MODULE__{
          ets: :ets.table(),
          seed_folders:
            :not_set
            | %{
                regions: String.t(),
                region_info: String.t()
              },
          worker: Worker.t()
        }

  @type search_result() :: {:ok, Region.t()} | {:error, Region.NotFoundError.t()}

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  @spec get(String.t(), Worker.t()) :: search_result()
  def get("" <> code, %Worker{instance_name: name}) do
    with {:error, :not_found} <- GenServer.call(name, {:get, code}) do
      {:error, Region.NotFoundError.exception(code: code)}
    end
  end

  def get!("" <> code, %Worker{} = worker) do
    case get(code, worker) do
      {:ok, region} -> region
      {:error, error} -> raise error
    end
  end

  def get_all(%Worker{instance_name: name} \\ Ebird.get_instance_child(:RegionETS)) do
    GenServer.call(name, :get_all)
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

  def handle_call(:get_all, _from, %__MODULE__{} = state) do
    {:reply, get_all_from_ets(state), state}
  end

  @impl GenServer
  def handle_cast({:save, %Region{} = region}, %__MODULE__{} = state) do
    true = do_save(state, region)
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:set_seed_folders, %__MODULE__{} = state) do
    {:noreply, set_seed_folders(state), {:continue, :seed}}
  end

  def handle_continue(:seed, %__MODULE__{seed_folders: :not_set} = state) do
    {:noreply, state, {:continue, :set_seed_folders}}
  end

  def handle_continue(:seed, %__MODULE__{seed_folders: %{}} = state) do
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
    |> Keyword.put_new(:seed_folders, :not_set)
    |> Keyword.put_new_lazy(:ets, fn -> :ets.new(__MODULE__, []) end)
    |> __struct__()
  end

  @spec set_seed_folders(t()) :: t()
  defp set_seed_folders(%__MODULE__{} = state) do
    {:ok, regions} =
      :Regions
      |> Ebird.get_instance_child()
      |> Worker.full_data_folder_path()

    {:ok, region_info} =
      :RegionInfo
      |> Ebird.get_instance_child()
      |> Worker.full_data_folder_path()

    %{state | seed_folders: %{regions: regions, region_info: region_info}}
  end

  defp do_save(%__MODULE__{ets: ets}, %Region{code: code} = region) do
    :ets.insert(ets, {code, region})
  end

  @spec get_from_ets(t(), String.t()) :: search_result()
  defp get_from_ets(%__MODULE__{ets: ets}, "" <> code) do
    case :ets.lookup(ets, code) do
      [{^code, %Region{} = region}] -> {:ok, region}
      [] -> {:error, :not_found}
    end
  end

  defp get_all_from_ets(%__MODULE__{ets: ets}) do
    ets
    |> :ets.tab2list()
    |> Enum.map(&elem(&1, 1))
  end

  defp read_file(%__MODULE__{seed_folders: %{}} = state, folder_key, "" <> file_name) do
    with {:ok, data} <-
           state.seed_folders
           |> Map.fetch!(folder_key)
           |> Path.join(file_name <> ".json")
           |> File.read() do
      Jason.decode!(data)
    end
  end

  defp seed_cache(%__MODULE__{} = state) do
    state
    |> parse_many_with_info!("all-countries")
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
    |> parse_many_with_info!(code <> "-" <> Atom.to_string(level))
    |> Enum.each(&do_save(state, &1))
  end

  defp parse_many_with_info!(%__MODULE__{} = state, file_name) do
    state
    |> read_file(:regions, file_name)
    |> Enum.map(&Region.parse!/1)
    |> Enum.map(&add_info!(&1, state))
  end

  defp add_info!(%Region{info: :unknown} = region, %__MODULE__{} = state) do
    %RegionInfo.Response{data: %RegionInfo{} = info} =
      state
      |> read_file(:region_info, region.code)
      |> case do
        {:error, :enoent} ->
          raise BirdSong.FileError.exception(region: region)

        data ->
          RegionInfo.Response.parse(data, {:region_info, region})
      end

    %{region | info: info}
  end
end
