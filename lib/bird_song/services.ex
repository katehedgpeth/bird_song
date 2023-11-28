defmodule BirdSong.Services do
  use Supervisor

  alias __MODULE__.{
    InjectableChildSpecs,
    DataFile,
    Ebird,
    Flickr,
    XenoCanto,
    Service,
    Worker
  }

  @env Mix.env()

  @recordings :bird_song
              |> Application.compile_env!(__MODULE__)
              |> Keyword.fetch!(:recordings)

  @services [
    DataFile,
    Ebird,
    Flickr,
    @recordings
  ]

  defstruct ebird: Ebird,
            images: Flickr,
            recordings: %Service{
              module: @recordings
            },
            data_file: "data"

  @type t() :: %__MODULE__{
          ebird: Ebird.t(),
          images: Flickr.t(),
          recordings: Service.t(),
          data_file: DataFile.t()
        }

  @type base_urls_map() :: %{
          required(Ebird) => String.t(),
          required(Flickr) => String.t(),
          required(XenoCanto) => String.t()
        }
  @type base_urls_opt() :: {:base_urls, base_urls_map()}

  @type service_struct() :: Ebird.t() | Flickr.t() | DataFile.t()

  @type service_key() :: :ebird | :images | :recordings | :data_file

  @type service_opts() :: {module(), Keyword.t()}

  defguard is_service_key(atom) when atom in [:ebird, :images, :recordings]

  #########################################################
  #########################################################
  ##
  ##  SUPERVISOR CALLBACKS
  ##
  #########################################################

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: instance_name(opts))
  end

  @impl Supervisor
  def init(opts) do
    opts
    |> child_specs()
    |> Supervisor.init(strategy: :one_for_one)
  end

  @spec child_specs(keyword()) :: nil | list()
  def child_specs!() do
    [DataFile | api_services] = @services

    api_services
    |> Enum.reduce([], &[{&1, [service_name: &1]} | &2])
    |> Keyword.put(DataFile, name: DataFile)
  end

  def child_specs([]), do: child_specs!()

  def child_specs(opts) when is_list(opts) and @env === :test do
    InjectableChildSpecs.child_specs(opts)
  end

  @spec all() :: {:error, :not_alive} | t()
  def all() do
    all(__MODULE__)
  end

  @spec all(Worker.t() | Service.t() | module() | pid()) :: t() | {:error, :not_alive}
  def all(%Worker{parent: %Service{} = parent}) do
    all(parent)
  end

  def all(%Service{} = service) do
    service
    |> Service.get_parent()
    |> all()
  end

  def all(instance) when is_atom(instance) or is_pid(instance) do
    instance
    |> GenServer.whereis()
    |> case do
      nil ->
        {:error, :not_alive}

      pid when is_pid(pid) ->
        pid
        |> Supervisor.which_children()
        |> Enum.map(&do_all(&1, instance))
        |> __struct__()
    end
  end

  def child_modules() do
    @services
  end

  def module_to_struct_key(DataFile), do: :data_file
  def module_to_struct_key(Ebird), do: :ebird
  def module_to_struct_key(Flickr), do: :images
  def module_to_struct_key(XenoCanto), do: :recordings

  def service_atom(DataFile), do: :DataFile
  def service_atom(Ebird), do: :Ebird
  def service_atom(Flickr), do: :Flickr
  def service_atom(XenoCanto), do: :XenoCanto

  def service_instance_name(parent, module)
      when is_atom(parent) and
             (module in @services or module === XenoCanto) do
    Module.concat(parent, service_atom(module))
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec do_all({module(), pid, :supervisor, [module()]}, module | atom()) ::
          {service_key(), service_struct()}
  defp do_all({DataFile, pid, :worker, [DataFile]}, instance_name) when is_pid(pid) do
    {module_to_struct_key(DataFile),
     instance_name
     |> service_instance_name(DataFile)
     |> Agent.get(& &1)}
  end

  defp do_all({module, pid, :supervisor, [module]}, instance_name) when is_pid(pid) do
    {
      module_to_struct_key(module),
      instance_name
      |> service_instance_name(module)
      |> module.services()
    }
  end

  defp instance_name([]) do
    __MODULE__
  end

  defp instance_name(opts) when @env === :test do
    Keyword.get(opts, :name, __MODULE__)
  end
end
