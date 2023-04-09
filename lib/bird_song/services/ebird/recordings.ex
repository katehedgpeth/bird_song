defmodule BirdSong.Services.Ebird.Recordings do
  use BirdSong.Services.ThrottledCache,
    data_folder_path: "data/recordings/ebird",
    ets_opts: [],
    ets_name: :ebird_recordings,
    base_url: "https://search.macaulaylibrary.org",
    scraper: __MODULE__.Playwright,
    throttler: BirdSong.Services.RequestThrottlers.MacaulayLibrary

  alias BirdSong.Data.Scraper.TimeoutError
  alias BirdSong.Data.Scraper.BadResponseError

  alias BirdSong.{
    Bird,
    Services.Helpers
  }

  alias BirdSong.Services.ThrottledCache, as: TC

  @type raw_response() :: {:ok, [Map.t()]} | {:error, any()}

  def base_url() do
    Helpers.get_env(__MODULE__, :base_url)
  end

  def endpoint(%Bird{}) do
    "catalog"
  end

  def params(%Bird{species_code: code}) do
    %{
      "taxonCode" => code,
      "mediaType" => "audio"
    }
  end

  @spec successful_response?({:ok, [Map.t()]} | {:error, any()}) :: boolean()
  def successful_response?({:ok, [%{} | _]}), do: true
  def successful_response?({:ok, []}), do: false
  def successful_response?({:error, _}), do: false

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:scraper_info, _from, %TC.State{scraper: scraper} = state) do
    {:reply, scraper, state}
  end

  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

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
