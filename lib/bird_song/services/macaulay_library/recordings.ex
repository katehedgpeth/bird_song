defmodule BirdSong.Services.MacaulayLibrary.Recordings do
  use BirdSong.Services.ThrottledCache,
    ets_opts: [],
    ets_name: :macaulay_library_recordings

  alias BirdSong.{
    Bird,
    Data.Scraper.TimeoutError,
    Data.Scraper.BadResponseError,
    Services.MacaulayLibrary,
    Services.ThrottledCache
  }

  alias BirdSong.Services.ThrottledCache, as: TC
  @type raw_response() :: {:ok, [Map.t()]} | {:error, any()}

  @impl ThrottledCache
  def endpoint(%Bird{}) do
    "catalog"
  end

  @impl ThrottledCache
  def params(%Bird{species_code: code}) do
    %{
      "taxonCode" => code,
      "mediaType" => "audio"
    }
  end

  @impl ThrottledCache
  def response_module() do
    MacaulayLibrary.Response
  end

  @impl GenServer
  def handle_info({ref, {:error, %BadResponseError{status: 404, url: url}}}, state)
      when is_reference(ref) do
    super({ref, {:error, {:not_found, url}}}, state)
  end

  def handle_info({ref, {:error, %BadResponseError{status: status} = error}}, state)
      when is_reference(ref) and status in 500..599 do
    super({ref, {:error, {:bad_response, error}}}, state)
  end

  def handle_info({ref, {:error, %TimeoutError{} = error}}, state) do
    super({ref, {:error, {:timeout, error}}}, state)
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
