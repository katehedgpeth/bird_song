defmodule BirdSong.Services.DataFile.Data do
  alias BirdSong.{
    Services.Service,
    Services.ThrottledCache
  }

  @enforce_keys [:request, :service]
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

  alias BirdSong.Services.ThrottledCache
  alias BirdSong.Services.{Helpers, Service}

  alias __MODULE__.Data

  @enforce_keys [:data_folder_path]
  defstruct [
    :data_folder_path,
    data_file_name_fn: &ThrottledCache.data_file_name/1,
    overwrite?: false,
    listeners: []
  ]

  @type error() :: :not_alive | :file.posix() | :bad_response | :forbidden_service

  @spec read(Data.t(), pid()) :: {:ok, String.t()} | {:error, {:file.posix(), String.t()}}
  def read(%Data{} = data, instance) when is_pid(instance) do
    GenServer.call(instance, {:read, data})
  end

  @spec write(Data.t(), pid | atom) :: :ok | {:error, error()}
  def write(%Data{} = data, instance) when is_pid(instance) do
    case Process.alive?(instance) do
      true -> GenServer.cast(instance, {:write, data})
      false -> {:error, {:not_alive, instance}}
    end
  end

  def register_listener(instance) when is_pid(instance) or is_atom(instance) do
    GenServer.cast(instance, {:register_listener, self()})
  end

  defp data_file_path(%Data{request: request}, %__MODULE__{
         data_file_name_fn: data_file_name_fn,
         data_folder_path: path
       }) do
    path
    |> Path.join(data_file_name_fn.(request) <> ".json")
    |> Path.relative_to_cwd()
  end

  def log_level(%{written?: true}), do: :info

  def log_level(%{written?: false}), do: :warning

  defp log(%Data{} = data, %{} = specifics) do
    data
    |> Map.from_struct()
    |> Map.delete(:request)
    |> Map.delete(:response)
    |> Map.update!(:service, fn %Service{module: module} -> module end)
    |> Map.merge(specifics)
    |> Helpers.log(__MODULE__, log_level(specifics))
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
    {:ok, __struct__(opts)}
  end

  def handle_call({:read, %Data{} = data}, _from, %__MODULE__{} = state) do
    path = data_file_path(data, state)

    result =
      case File.read(path) do
        {:error, error} -> {:error, {error, path}}
        result -> result
      end

    {:reply, result, state}
  end

  def handle_call({:data_file_path, %Data{} = data}, _from, %__MODULE__{} = state) do
    {:reply, data_file_path(data, state), state}
  end

  def handle_cast(
        {:write,
         %Data{
           response: {:ok, %HTTPoison.Response{status_code: 200, body: body}}
         } = data},
        %__MODULE__{} = state
      ) do
    do_write(body, data, state)
    {:noreply, state}
  end

  def handle_cast(
        {:write, %Data{response: {:ok, [_ | _] = body}} = data},
        %__MODULE__{} = state
      ) do
    body
    |> Jason.encode!()
    |> do_write(data, state)

    {:noreply, state}
  end

  def handle_cast({:write, %Data{} = data}, %__MODULE__{} = state) do
    path = data_file_path(data, state)
    log_and_send_messages(%{written?: false, error: :bad_response, path: path}, data, state)
    {:noreply, state}
  end

  def handle_cast({:register_listener, listener}, state) do
    {:noreply, %{state | listeners: [listener | state.listeners]}}
  end

  defp do_write(body, %Data{} = data, state) do
    path = data_file_path(data, state)

    path
    |> File.write(body)
    |> case do
      :ok ->
        %{written?: true, path: path}

      {:error, reason} ->
        %{written?: false, error: :write_error, reason: reason, path: path}
    end
    |> log_and_send_messages(data, state)
  end
end
