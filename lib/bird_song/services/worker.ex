defmodule BirdSong.Services.Worker do
  alias BirdSong.{
    Services,
    Services.Ebird,
    Services.Service
  }

  @callback do_init(Keyword.t()) :: {:ok, struct()} | {:ok, struct(), {:continue, any()}}

  @derive {Inspect, only: [:instance_name, :module]}

  @struct_keys [
    :instance_name,
    :atom,
    :module,
    :parent
  ]

  @never_write_to_disk [Ebird.Observations]

  @enforce_keys @struct_keys
  defstruct @struct_keys

  @type t() :: %__MODULE__{
          instance_name: Services.Supervisor.instance_worker_name(),
          module: Services.Supervisor.instance_worker_module(),
          atom: Services.Supervisor.instance_worker_atom(),
          parent: Services.Service.t()
        }

  @type data_folder_error() :: {:error, :never_write_to_disk}

  def call(%__MODULE__{instance_name: name}, message) do
    GenServer.call(name, message)
  end

  @spec full_data_folder_path(t()) :: {:ok, String.t()} | data_folder_error()
  def full_data_folder_path(%__MODULE__{parent: %Service{}} = instance) do
    with {:ok, path} <- data_folder_path(instance) do
      {:ok,
       instance.parent
       |> Services.all()
       |> Map.fetch!(:data_file)
       |> Map.fetch!(:parent_folder)
       |> Path.join(path)}
    end
  end

  @spec data_folder_path(t()) :: {:ok, String.t()} | {:error, :never_write_to_disk}
  def data_folder_path(%__MODULE__{module: module}) when module in @never_write_to_disk do
    {:error, :never_write_to_disk}
  end

  def data_folder_path(%__MODULE__{module: module, parent: %Service{module: parent}})
      when module not in @never_write_to_disk do
    {:ok,
     module
     |> Service.data_type()
     |> Atom.to_string()
     |> Path.join(
       parent
       |> Macro.underscore()
       |> Path.split()
       |> List.last()
     )}
  end

  def data_file_name(%__MODULE__{module: module}, request) do
    apply(module, :data_file_name, [request])
  end

  @spec get_sibling(
          t(),
          Services.Supervisor.service_module()
        ) :: t()
  def get_sibling(
        %__MODULE__{} = worker,
        sibling_atom
      ) do
    apply(worker.parent.module, :get_instance_child, [worker.parent.name, sibling_atom])
  end

  def response_module(%__MODULE__{module: module}) when module !== nil do
    if Kernel.function_exported?(module, :response_module, 0) do
      module.response_module()
    else
      Module.concat(module, :Response)
    end
  end

  def parse_from_disk(%__MODULE__{} = worker, request_data) do
    worker.module.parse_from_disk(request_data, worker.instance_name)
  end

  def parse_response(%__MODULE__{} = worker, response, request) do
    worker
    |> response_module()
    |> apply(:parse, [response, request])
  end

  def read_from_disk(%__MODULE__{} = worker, request_data) do
    worker.module.read_from_disk(request_data, worker)
  end

  def register_request_listener(%__MODULE__{} = worker) do
    worker.module.register_request_listener(worker)
  end

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      use GenServer

      @behaviour BirdSong.Services.Worker

      alias BirdSong.Services.Worker

      @start_link_option_keys Keyword.fetch!(opts, :option_keys)

      def start_link_option_keys() do
        @start_link_option_keys
      end

      def start_link(opts) do
        %Worker{instance_name: name} = Keyword.fetch!(opts, :worker)
        GenServer.start_link(__MODULE__, opts, name: name)
      end

      @impl GenServer
      def init(opts) do
        do_init(opts)
      end

      @impl GenServer
      def handle_call(:worker_info, _from, %{worker: %Worker{}} = state) do
        {:reply, state.worker, state}
      end
    end
  end
end
