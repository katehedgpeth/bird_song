defmodule BirdSong.Services.Service.NotStartedError do
  defexception [:module]

  def message(%__MODULE__{module: module}),
    do: """
    #{inspect(module)} service is not started!
    """
end

defmodule BirdSong.Services.Service do
  alias BirdSong.Services.{
    Ebird,
    Flickr,
    Helpers,
    MacaulayLibrary,
    XenoCanto
  }

  defstruct [:module, :name]

  @type t() :: %__MODULE__{
          module: module(),
          name: module() | atom()
        }

  @type response() ::
          XenoCanto.Response.t() | Flickr.Response.t() | Ebird.Observations.Response.t()

  def data_type(%__MODULE__{module: module}), do: data_type(module)
  def data_type(XenoCanto.Recordings), do: :recordings
  def data_type(MacaulayLibrary.Recordings), do: :recordings
  def data_type(Flickr.PhotoSearch), do: :images
  def data_type(Ebird.Observations), do: :observations
  def data_type(Ebird.RegionSpeciesCodes), do: :region_species_codes
  def data_type(Ebird.Regions), do: :regions
  def data_type(Ebird.RegionInfo), do: :region_info

  def data_type(module) do
    Helpers.log(%{message: "unknown_service", module: module}, __MODULE__, :warning)
    :misc
  end

  def get_parent(%__MODULE__{} = service) do
    service
    |> BirdSong.Services.Supervisor.whereis!()
    |> Process.info()
    |> Keyword.fetch!(:dictionary)
    |> Keyword.fetch!(:"$ancestors")
    |> List.first()
  end

  def module(%__MODULE__{module: module}), do: module
end
