defmodule BirdSong.Services.Service.NotStartedError do
  defexception [:module]

  def message(%__MODULE__{module: module}),
    do: """
    #{inspect(module)} service is not started!
    """
end

defmodule BirdSong.Services.Service do
  alias BirdSong.Services.{Ebird, Flickr, XenoCanto, GenServers, Helpers}

  defstruct [:module, :whereis, :response, :exit_reason]

  @type t() :: %__MODULE__{
          module: atom(),
          whereis: GenServer.server(),
          response: Helpers.api_response() | nil,
          exit_reason: atom() | nil
        }

  @type response() :: XenoCanto.Response.t() | Flickr.Response.t() | Ebird.Response.t()

  def data_folder_path(%__MODULE__{} = service) do
    service
    |> module()
    |> apply(:data_folder_path, [service])
  end

  def data_type(%__MODULE__{module: module}), do: data_type(module)
  def data_type(XenoCanto), do: :recordings
  def data_type(Ebird.Recordings), do: :recordings
  def data_type(Flickr), do: :images
  def data_type(Ebird), do: :observations

  def data_type(module) do
    Helpers.log(%{message: "unknown_service", module: module}, __MODULE__, :warning)
    :misc
  end

  def ensure_started!(%__MODULE__{} = service) do
    ensure_started(service, raise?: true)
  end

  def ensure_started(%__MODULE__{} = service) do
    ensure_started(service, raise?: false)
  end

  def ensure_started(%__MODULE__{whereis: pid} = service, _raise?) when is_pid(pid), do: service

  def ensure_started(%__MODULE__{module: module} = service, raise?: raise?) do
    case {GenServer.whereis(module), raise?} do
      {nil, true} ->
        raise __MODULE__.NotStartedError, module: module

      {nil, false} ->
        {:ok, pid} = DynamicSupervisor.start_child(GenServers, module)
        %{service | whereis: pid}

      {pid, _} ->
        %{service | whereis: pid}
    end
  end

  def module(%__MODULE__{module: module}), do: module

  def register_request_listener(%__MODULE__{module: module, whereis: whereis}) do
    module.register_request_listener(whereis)
  end
end
