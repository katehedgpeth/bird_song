defmodule BirdSong.Services.DataFile.Data do
  alias BirdSong.{
    Services.Service,
    Services.ThrottledCache
  }

  defstruct [:response, :request, :service]

  @type t() :: %__MODULE__{
          request: ThrottledCache.request_data(),
          response: {:ok, HTTPoison.Response.t()} | nil,
          service: Service.t()
        }
end

defmodule BirdSong.Services.DataFile do
  require Logger
  use GenServer

  alias BirdSong.Services.{Helpers, Service}

  alias __MODULE__.Data

  defstruct overwrite?: false, listeners: []

  @type error() :: :not_alive | :file.posix() | :bad_response | :forbidden_service

  @spec read(Data.t()) :: {:ok, String.t()} | {:error, :file.posix()}
  def read(%Data{} = data) do
    data
    |> data_file_path()
    |> File.read()
  end

  @spec write(Data.t(), pid | atom) :: :ok | {:error, error()}
  def write(
        %Data{response: {:ok, %HTTPoison.Response{status_code: 200}}} = info,
        instance
      )
      when is_pid(instance) or is_atom(instance) do
    case whereis(instance) do
      {:ok, pid} ->
        GenServer.cast(pid, {:write, info})

      {:error, :not_alive} = error ->
        Helpers.log(:warning, __MODULE__, %{
          write: false,
          error: "data_file_instance_not_alive",
          instance: instance
        })

        error
    end
  end

  def register_listener(instance) when is_pid(instance) or is_atom(instance) do
    GenServer.cast(instance, {:register_listener, self()})
  end

  defp whereis(instance) when is_pid(instance) do
    case Process.alive?(instance) do
      true -> {:ok, instance}
      false -> {:error, :not_alive}
    end
  end

  defp whereis(instance) do
    case GenServer.whereis(instance) do
      nil -> {:error, :not_alive}
      pid_or_tuple -> {:ok, pid_or_tuple}
    end
  end

  defp data_file_name(%Data{service: %Service{name: service_module}, request: request}) do
    service_module
    |> apply(:data_file_name, [request])
    |> Kernel.<>(".json")
  end

  def data_file_path(%Data{service: service} = data) do
    service
    |> Map.fetch!(:name)
    |> apply(:data_folder_path, [service])
    |> Path.join(data_file_name(data))
    |> Path.relative_to_cwd()
  end

  def log_fn(%{written?: true}), do: &Logger.info/1

  def log_fn(%{written?: false}), do: &Logger.warn/1

  defp log(%Data{} = data, %{} = specifics) do
    data
    |> Map.from_struct()
    |> Map.delete(:request)
    |> Map.delete(:response)
    |> Map.update!(:service, fn %Service{name: name} -> name end)
    |> Map.merge(specifics)
    |> Enum.map(fn {key, val} -> "#{key}=#{val}" end)
    |> Enum.join(" ")
    |> log_fn(specifics).()
  end

  defp log_and_send_messages(%{} = info, %Data{} = data, %__MODULE__{listeners: listeners}) do
    log(data, info)

    Enum.each(listeners, &send_message(&1, data, info))
  end

  defp send_message(listener, %Data{} = data, %{} = info) do
    send(
      listener,
      {__MODULE__,
       data
       |> Map.from_struct()
       |> Map.merge(info)
       |> message()}
    )
  end

  defp message(%{written?: false} = info) do
    {:error, info}
  end

  defp message(%{written?: true} = info) do
    {:ok, info}
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    {:ok, struct(%__MODULE__{}, opts)}
  end

  def handle_cast(
        {:write,
         %Data{
           response: {:ok, %HTTPoison.Response{status_code: 200, body: body}}
         } = data},
        %__MODULE__{} = state
      ) do
    path = data_file_path(data)

    path
    |> File.write(body)
    |> case do
      :ok ->
        %{written?: true, path: path}

      {:error, reason} ->
        %{written?: false, error: :write_error, reason: reason, path: path}
    end
    |> log_and_send_messages(data, state)

    {:noreply, state}
  end

  def handle_cast({:register_listener, listener}, state) do
    {:noreply, %{state | listeners: [listener | state.listeners]}}
  end
end
