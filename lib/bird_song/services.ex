defmodule BirdSong.Services do
  use Supervisor

  alias __MODULE__.{
    DataFile,
    Ebird,
    Flickr,
    MacaulayLibrary,
    XenoCanto,
    Service,
    Worker
  }

  @recordings :bird_song
              |> Application.compile_env!(__MODULE__)
              |> Keyword.fetch!(:recordings)

  @services [
    DataFile,
    Ebird,
    Flickr,
    MacaulayLibrary
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
          required(MacaulayLibrary) => String.t(),
          required(XenoCanto) => String.t()
        }
  @type base_urls_opt() :: {:base_urls, base_urls_map()}

  @type service_struct() :: Ebird.t() | Flickr.t() | MacaulayLibrary.t() | DataFile.t()

  @type service_key() :: :ebird | :images | :recordings | :data_file

  @type service_opts() :: {module(), Keyword.t()}

  def all() do
    all(__MODULE__)
  end

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
    |> Supervisor.which_children()
    |> case do
      children when is_list(children) ->
        children
        |> Enum.map(&do_all(&1, instance))
        |> __struct__()
    end
  end

  def module_to_struct_key(DataFile), do: :data_file
  def module_to_struct_key(Ebird), do: :ebird
  def module_to_struct_key(Flickr), do: :images
  def module_to_struct_key(MacaulayLibrary), do: :recordings
  def module_to_struct_key(XenoCanto), do: :recordings

  def service_atom(DataFile), do: :DataFile
  def service_atom(Ebird), do: :Ebird
  def service_atom(Flickr), do: :Flickr
  def service_atom(MacaulayLibrary), do: :MacaulayLibrary
  def service_atom(XenoCanto), do: :XenoCanto

  def service_instance_name(opts, service) when is_list(opts) do
    opts
    |> injected_instance_name()
    |> service_instance_name(service)
  end

  def service_instance_name(parent, module)
      when module in @services or module === XenoCanto do
    Module.concat(parent, service_atom(module))
  end

  defp injected_instance_name(opts) do
    Keyword.get(opts, :name, __MODULE__)
  end

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: injected_instance_name(opts))
  end

  @impl Supervisor
  def init(opts) when is_list(opts) do
    opts
    |> Keyword.pop(:env, Mix.env())
    |> child_specs()
    |> Supervisor.init(strategy: :one_for_one)
  end

  def child_specs({env, opts}) when env in [:dev, :prod] do
    # Services do not take options outside of tests.
    # We allow a different env to be injected in order to test
    # that things work as expected outside of the test environment.
    if length(opts) > 0 and Mix.env() !== :test do
      raise ArgumentError.exception("Do not pass options to Services outside of tests")
    end

    Enum.map(
      @services,
      &{
        &1,
        [
          {
            case &1 do
              DataFile -> :name
              _ -> :service_name
            end,
            service_instance_name(opts, &1)
          }
        ]
      }
    )
  end

  def child_specs({:test, opts}) when is_list(opts) do
    [DataFile | Keyword.get(opts, :service_modules, @services)]
    |> Enum.uniq()
    |> Enum.map(&child_spec(&1, opts, :test))
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

  defp child_spec(DataFile, opts, :test) do
    {DataFile,
     Keyword.merge(
       [
         parent_folder: Keyword.get(opts, :parent_data_folder, "data"),
         overwrite?: Keyword.get(opts, :overwrite_data?, false),
         name: service_instance_name(opts, DataFile)
       ],
       Keyword.get(opts, DataFile, [])
     )}
  end

  defp child_spec(module, opts, :test) do
    {module,
     opts
     |> put_test_overrides(module, Keyword.get(opts, module, []))
     |> Keyword.drop([:name, :base_urls])}
  end

  defp put_test_overrides(opts, module, custom_service_opts)
       when is_atom(module) and
              is_list(opts) and
              is_list(custom_service_opts) do
    opts
    |> Keyword.take([:allow_external_calls?, :throttle_ms])
    |> put_test_url(module, opts)
    |> Keyword.merge(custom_service_opts)
    |> Keyword.put(:service_name, service_instance_name(opts, module))
  end

  @spec put_test_url(Keyword.t(), module(), Keyword.t()) :: Keyword.t()
  defp put_test_url(service_opts, module, opts) do
    opts
    |> Keyword.get(:base_urls, [])
    |> Keyword.get(module)
    |> case do
      nil -> service_opts
      "" <> _ = base_url -> Keyword.put(service_opts, :base_url, base_url)
    end
  end
end
