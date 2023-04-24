defmodule BirdSong.Services.Ebird do
  use BirdSong.Services.Supervisor

  alias BirdSong.Services.Supervisor, as: Sup

  alias BirdSong.Services.{
    RequestThrottler,
    Service
  }

  alias __MODULE__.{
    Observations,
    Regions,
    RegionSpeciesCodes
  }

  @base_url "https://api.ebird.org"

  @token :bird_song
         |> Application.compile_env(__MODULE__)
         |> Keyword.fetch!(:token)

  @type request_data() ::
          Observations.request_data()
          | Regions.request_data()
          | RegionInfo.request_data()
          | RegionSpeciesCodes.request_data()

  @type child_name_t() ::
          :Observations
          | :RegionInfo
          | :RegionETS
          | :RegionSpeciesCodes
          | :Regions
          | :RequestThrottler

  @type t() :: %__MODULE__{
          Observations: Service.t(),
          RegionInfo: Service.t(),
          RegionSpeciesCodes: Service.t(),
          Regions: Service.t()
        }

  @type opt() :: {:service_name, Sup.test_instance()}

  #########################################################
  #########################################################
  ##
  ##  ATTRIBUTES
  ##
  #########################################################

  # @ets_name Module.concat([:Regions, :RegionETS])
  @caches [:Observations, :RegionSpeciesCodes, :Regions, :RegionInfo]

  @child_names [
    :RequestThrottler,
    :RegionETS
    | @caches
  ]

  @default_opts [
    service_name: __MODULE__,
    base_url: "https://api.ebird.org"
  ]

  @opt_keys [
    :base_url,
    :data_folder_path,
    :service_name,
    :throttle_ms
  ]
  @opt_keys_set MapSet.new(@opt_keys)

  @enforce_keys @caches
  defstruct @caches

  #########################################################
  #########################################################
  ##
  ##  GUARDS
  ##
  #########################################################

  defguard is_child_name(name) when name in @child_names

  #########################################################
  #########################################################
  ##
  ##  SUPERVISOR CALLBACKS
  ##
  #########################################################

  def start_link(opts) do
    opts
    |> raise_unused_opts()
    |> with_default_opts()
    |> Sup.start_link(__MODULE__)
  end

  def init(opts) do
    opts
    |> child_specs()
    |> Elixir.Supervisor.init(strategy: :one_for_one)
  end

  if Mix.env() === :test do
    def child_specs___test(opts) do
      child_specs(opts)
    end
  end

  defp child_specs(opts) when is_list(opts) do
    opts
    |> with_default_opts()
    |> raise_unused_opts()
    |> do_child_specs()
  end

  defp do_child_specs(opts) do
    Enum.map(
      @child_names,
      &{
        child_module(&1),
        opts_for_child(opts, &1)
      }
    )
  end

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  def base_url(), do: @base_url

  @spec base_url(Sup.name(:Ebird)) :: String.t()
  def base_url(instance_name) do
    when_service_instance_name instance_name, __MODULE__ do
      %{RequestThrottler: %Service{whereis: whereis}} = map_of_child_pids(instance_name)

      GenServer.call(whereis, :base_url)
    end
  end

  def services() do
    default_service_name()
    |> services()
  end

  def services(service) do
    when_service_instance_name service, __MODULE__ do
      @caches
      |> Enum.map(
        &{&1,
         get_instance_child(
           map_of_child_pids(service),
           service,
           &1
         )}
      )
      |> __struct__()
    end
  end

  def child_name(opts, child)
      when is_list(opts) and is_child_name(child) do
    opts
    |> Keyword.fetch!(:service_name)
    |> child_name(child)
  end

  def child_name(service, child) when is_child_name(child) do
    when_service_instance_name service, __MODULE__ do
      concat_name(service, child)
    end
  end

  def get_instance_child(service_instance, child) do
    when_service_instance_name service_instance, __MODULE__ do
      service_instance
      |> map_of_child_pids()
      |> get_instance_child(service_instance, child)
    end
  end

  def token_header() do
    {"x-ebirdapitoken", @token}
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  def concat_name(parent, child) when is_atom(parent) and is_child_name(child) do
    [parent, child]
    |> List.flatten()
    |> Module.concat()
  end

  @spec default_service_name() :: Sup.service_name()
  def default_service_name() do
    Keyword.fetch!(@default_opts, :service_name)
  end

  @spec child_module(atom()) :: atom()
  defp child_module(:RequestThrottler), do: RequestThrottler
  defp child_module(child) when is_child_name(child), do: concat_name(__MODULE__, child)

  defp get_instance_child(%{} = supervisor_children, service_instance, child)
       when is_child_name(child) do
    supervisor_children
    |> Map.fetch!(child_module(child))
    |> do_get_instance_child(service_instance, child)
  end

  defp do_get_instance_child(child_pid, service_instance, child)
       when is_child_name(child) do
    %Service{
      whereis: child_pid,
      name: child_name(service_instance, child),
      module: child_module(child)
    }
  end

  defp opts_for_child(opts, child) when is_child_name(child) do
    opts
    |> Keyword.put(:name, child_name(opts, child))
    |> do_opts_for_child(child)
    |> Keyword.drop([:service_name])
  end

  defp do_opts_for_child(opts, :RegionETS) do
    Keyword.take(opts, [:name])
  end

  defp do_opts_for_child(opts, :RequestThrottler) do
    Keyword.drop(opts, [:data_folder_path, :throttler])
  end

  defp do_opts_for_child(opts, child) when child in @caches do
    opts
    |> Keyword.put(:throttler, child_name(opts, :RequestThrottler))
    |> Keyword.drop([:throttle_ms])
  end

  defp raise_unused_opts(opts) do
    opts
    |> Keyword.keys()
    |> MapSet.new()
    |> MapSet.difference(@opt_keys_set)
    |> MapSet.to_list()
    |> case do
      [] -> opts
      [_ | _] = keys -> raise Sup.UnknownOptionKeyError.exception(keys: keys, module: __MODULE__)
    end
  end

  defp with_default_opts(opts) do
    @default_opts
    |> Keyword.merge(opts)
  end
end
