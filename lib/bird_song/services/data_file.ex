defmodule BirdSong.Services.DataFile.Data do
  alias BirdSong.Services.Helpers

  alias BirdSong.{
    Services.ThrottledCache,
    Services.Worker
  }

  @enforce_keys [:request, :worker]
  defstruct [:request, :response, :worker]

  @type t() :: %__MODULE__{
          request: ThrottledCache.request_data(),
          worker: Worker.t(),
          response: {:ok, Helpers.jason_decoded()} | {:error, any()} | nil
        }
end

defmodule BirdSong.Services.DataFile do
  require Logger
  use Agent

  alias BirdSong.{
    Services,
    Services.Helpers,
    Services.Service,
    Services.Worker
  }

  alias __MODULE__.Data

  @enforce_keys [:parent_folder]
  defstruct [
    :parent_folder,
    overwrite?: false,
    listeners: []
  ]

  @type t() :: %__MODULE__{
          parent_folder: String.t(),
          overwrite?: boolean(),
          listeners: [pid]
        }

  @type error() :: :not_alive | :file.posix() | :bad_response | :forbidden_service

  defguard is_json(response)
           when is_list(response) or
                  (is_map(response) and not is_struct(response))

  # Executes the callback only if the worker allows reading from disk.
  # Callback takes 2 arguments - %Data{}, and the file path string
  defp with_full_file_path(%Data{} = data, callback) when is_function(callback) do
    with {:ok, inner_path} <- Worker.data_folder_path(data.worker),
         "" <> file_path <- data_file_path(data, inner_path) do
      callback.(data, file_path)
    end
  end

  @spec create_data_folder(Worker.t()) :: :ok | {:error, :never_write_to_disk}
  def create_data_folder(%Worker{} = worker) do
    with {:ok, worker_path} <- Worker.data_folder_path(worker),
         {:ok, state} <- worker |> get_state() |> validate_parent_folder() do
      path = Path.join(state.parent_folder, worker_path)

      message =
        case File.exists?(path) do
          true ->
            :folder_exists

          false ->
            :ok = File.mkdir_p!(path)
            :folder_created
        end

      Enum.each(
        state.listeners,
        &send(&1, {
          __MODULE__,
          %{
            message: message,
            path: path,
            state: state,
            worker: worker
          }
        })
      )
    end
  end

  def log_level(%{written?: true}), do: :info

  def log_level(%{written?: false}), do: :warning

  @spec read(Data.t()) ::
          {:ok, String.t()}
          | {:error, {:file.posix(), String.t()}}
          | Worker.data_folder_error()
  def read(%Data{} = data) do
    with_full_file_path(data, &do_read/2)
  end

  @spec register_listener(module()) :: :ok
  def register_listener(data_file_instance) when is_atom(data_file_instance) do
    Agent.update(data_file_instance, __MODULE__, :do_register_listener, [self()])
  end

  def do_register_listener(%__MODULE__{} = state, listener) when is_pid(listener) do
    %{state | listeners: Enum.uniq([listener | state.listeners])}
  end

  @spec write(Data.t()) :: :ok | Worker.data_folder_error()
  def write(%Data{} = data) do
    with_full_file_path(data, &do_write/2)
  end

  if Mix.env() === :test do
    @spec data_file_path(Data.t()) :: {:ok, String.t()} | Worker.data_folder_error()
    def data_file_path(%Data{} = data) do
      with_full_file_path(data, fn %Data{}, path -> {:ok, path} end)
    end
  end

  #########################################################
  #########################################################
  ##
  ##  PRIVATE METHODS
  ##
  #########################################################

  @spec data_file_path(Data.t(), String.t()) :: String.t()
  defp data_file_path(
         %Data{worker: worker, request: request},
         "" <> inner_path
       ) do
    %__MODULE__{parent_folder: parent_folder} = get_state(worker)

    parent_folder
    |> Path.join(inner_path)
    |> Path.join(Worker.data_file_name(worker, request) <> ".json")
  end

  @spec get_state(Data.t() | Worker.t() | Service.t()) :: t()
  defp get_state(%Data{worker: worker}) do
    get_state(worker)
  end

  defp get_state(%Worker{parent: parent}) do
    get_state(parent)
  end

  defp get_state(%Service{} = service) do
    service
    |> Service.get_parent()
    |> Services.service_instance_name(__MODULE__)
    |> Agent.get(& &1)
  end

  defp log(%Data{} = data, %{} = specifics) do
    data
    |> Map.from_struct()
    |> Map.delete(:request)
    |> Map.delete(:response)
    |> Map.update!(:worker, fn %{module: module} -> module end)
    |> Map.merge(specifics)
    |> Helpers.log(__MODULE__, log_level(specifics))
  end

  @spec log_and_send_messages(Map.t(), Data.t()) :: :ok
  defp log_and_send_messages(%{} = info, %Data{} = data) do
    log(data, info)

    data
    |> get_state()
    |> Map.fetch!(:listeners)
    |> Enum.each(&send_message(&1, data, info))
  end

  defp send_message(listener, %Data{} = data, %{} = info) do
    send(
      listener,
      {__MODULE__,
       data
       |> Map.from_struct()
       |> Map.merge(info)
       |> case do
         %{written?: false} = message -> {:error, message}
         %{written?: true} = message -> {:ok, message}
       end}
    )
  end

  @spec do_read(Data.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, {File.posix(), String.t()}}
  defp do_read(%Data{}, "" <> file_path) do
    with {:error, error} <- File.read(file_path) do
      {:error, {error, file_path}}
    end
  end

  defp do_write(%Data{response: {:ok, response}} = data, "" <> path) when is_json(response) do
    path
    |> File.write(Jason.encode!(response))
    |> case do
      :ok ->
        %{written?: true, path: path}

      {:error, reason} ->
        %{written?: false, error: :write_error, reason: reason, path: path}
    end
    |> log_and_send_messages(data)
  end

  defp do_write(%Data{response: {:error, _}} = data, "" <> path) do
    log_and_send_messages(
      %{
        written?: false,
        error: :bad_response,
        path: path
      },
      data
    )
  end

  defp validate_parent_folder(%__MODULE__{} = state) do
    case state.parent_folder do
      "data" <> _ -> {:ok, state}
      "tmp" <> _ -> {:ok, state}
      other -> {:error, {:bad_parent_folder, other}}
    end
  end

  #########################################################
  #########################################################
  ##
  ##  AGENT
  ##
  #########################################################

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)

    Agent.start_link(
      __MODULE__,
      :__struct__,
      [
        # ensure the path is always relative to the current working directory,
        # so we don't accidentally write files to random places on disk
        # when writing tests
        Keyword.update(opts, :parent_folder, "data", &Path.relative_to_cwd(&1))
      ],
      name: name
    )
  end
end
