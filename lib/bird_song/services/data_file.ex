defmodule BirdSong.Services.DataFile.Data do
  defstruct [:response, :bird, :service, :service_instance]
end

defmodule BirdSong.Services.DataFile do
  require Logger
  use GenServer

  alias BirdSong.Bird
  alias __MODULE__.Data

  defstruct overwrite?: false, listeners: []

  @bad_response_error {:error, :bad_response}

  @type error() :: :not_alive | :file.posix() | :bad_response | :forbidden_service

  @spec read(Data.t()) :: {:ok, String.t()} | {:error, :file.posix()}
  def read(%Data{bird: %Bird{}, service: service} = data) when is_atom(service) do
    data
    |> data_file_path()
    |> File.read()
  end

  @spec write(Data.t(), pid | atom) :: :ok | {:error, error()}
  def write(%Data{service: BirdSong.Services.Ebird}, _instance) do
    {:error, :forbidden_service}
  end

  def write(
        %Data{bird: %Bird{}, response: {:ok, %HTTPoison.Response{status_code: 200}}} = info,
        instance
      )
      when is_pid(instance) or is_atom(instance) do
    case whereis(instance) do
      {:ok, server} ->
        GenServer.cast(server, {:write, info})
        :ok

      error ->
        error
    end
  end

  def write(%Data{response: {:error, %HTTPoison.Error{}}}, _instance), do: @bad_response_error

  def write(%Data{response: {:ok, %HTTPoison.Response{}}}, _instance), do: @bad_response_error

  def remove(%Data{} = data) do
    data
    |> data_file_path()
    |> File.rm!()
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

  defp whereis(instance) when is_atom(instance) do
    case GenServer.whereis(instance) do
      nil -> {:error, :not_alive}
      pid_or_tuple -> {:ok, pid_or_tuple}
    end
  end

  defp data_file_name(%Bird{common_name: common_name}) do
    common_name
    |> String.replace(" ", "_")
    |> Kernel.<>(".json")
  end

  def data_file_path(%Data{bird: bird, service: service} = data) do
    service
    |> apply(:data_folder_path, [data])
    |> Path.join(data_file_name(bird))
    |> Path.relative_to_cwd()
  end

  def log_fn(%{written?: true}), do: &Logger.info/1

  def log_fn(%{written?: false}), do: &Logger.warn/1

  defp log(%Data{} = data, %{} = specifics) do
    {%Bird{common_name: common_name}, data} =
      data
      |> Map.from_struct()
      |> Map.pop!(:bird)

    data
    |> Map.put(:bird, common_name)
    |> Map.delete(:response)
    |> Map.delete(:service_instance)
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
    data
    |> data_file_path()
    |> File.write(body)
    |> case do
      :ok ->
        %{written?: true}

      {:error, reason} ->
        %{written?: false, error: :write_error, reason: reason}
    end
    |> log_and_send_messages(data, state)

    {:noreply, state}
  end

  def handle_cast({:register_listener, listener}, state) do
    {:noreply, %{state | listeners: [listener | state.listeners]}}
  end
end
