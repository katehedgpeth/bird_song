defmodule BirdSong.Services.Service.NotStartedError do
  defexception [:module]

  def message(%__MODULE__{module: module}),
    do: """
    #{inspect(module)} service is not started!
    """
end

defmodule BirdSong.Services.Service do
  alias BirdSong.Services.{Ebird, Flickr, XenoCanto, GenServers, Helpers}

  defstruct [:module, :name, :whereis, :response, :exit_reason]

  @type t() :: %__MODULE__{
          module: atom(),
          whereis: GenServer.server(),
          response: Helpers.api_response() | nil,
          exit_reason: atom() | nil
        }

  @type response() ::
          XenoCanto.Response.t() | Flickr.Response.t() | Ebird.Observations.Response.t()

  def data_file_name(%__MODULE__{module: module}, request) do
    apply(module, :data_file_name, [request])
  end

  def data_folder_path(%__MODULE__{} = service) do
    service
    |> module()
    |> apply(:data_folder_path, [service])
  end

  def data_type(%__MODULE__{module: module}), do: data_type(module)
  def data_type(XenoCanto), do: :recordings
  def data_type(MacaulayLibrary.Recordings), do: :recordings
  def data_type(Flickr), do: :images
  def data_type(Ebird.Observations), do: :observations
  def data_type(Ebird.RegionSpeciesCodes), do: :region_species_codes
  def data_type(Ebird.Regions), do: :regions

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

  def parse_from_disk(%__MODULE__{module: module, whereis: whereis}, request_data) do
    module.parse_from_disk(request_data, whereis)
  end

  def parse_response(%__MODULE__{} = service, response, request) do
    service
    |> response_module()
    |> apply(:parse, [response, request])
  end

  def read_from_disk(%__MODULE__{module: module, whereis: whereis}, request_data) do
    module.read_from_disk(request_data, whereis)
  end

  def response_module(%__MODULE__{module: module}) when module !== nil do
    if Kernel.function_exported?(module, :response_module, 0) do
      module.response_module()
    else
      Module.concat(module, :Response)
    end
  end

  def register_request_listener(%__MODULE__{module: module, whereis: whereis}) do
    module.register_request_listener(whereis)
  end
end
