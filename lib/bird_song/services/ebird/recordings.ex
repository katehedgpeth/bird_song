defmodule BirdSong.Services.Ebird.Recordings do
  use BirdSong.Services.ThrottledCache,
    data_folder_path: "data/recordings/ebird",
    ets_opts: [],
    ets_name: :ebird_recordings,
    base_url: "https://search.macaulaylibrary.org",
    scraper: __MODULE__.Playwright,
    seed_data?: true

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
    [
      {"taxonCode", code},
      {"mediaType", "audio"}
    ]
  end

  def get_from_api(
        %Bird{} = bird,
        %TC.State{scraper: {scraper_module, scraper_pid}} = state
      )
      when is_pid(scraper_pid) do
    scraper_pid
    |> scraper_module.run(bird)
    |> maybe_write_to_disk(bird, state)
    |> case do
      {:ok, [_ | _] = raw_recordings} ->
        {:ok, Response.parse(raw_recordings, bird)}

      {:ok, []} ->
        {:error, {:no_results, bird}}

      {:error, error} ->
        {:error, error}
    end
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

  def handle_call({:get_from_api, request}, from, %TC.State{scraper: scraper} = state) do
    super({:get_from_api, request}, from, %{
      state
      | scraper: start_scraper_instance(scraper, state)
    })
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

  defp start_scraper_instance(nil, %TC.State{}) do
    raise "Scraper instance is not set!"
  end

  defp start_scraper_instance(module, %TC.State{
         base_url: base_url,
         request_listeners: listeners,
         throttle_ms: throttle_ms
       })
       when is_atom(module) and module !== nil do
    {:ok, pid} =
      module.start_link(
        base_url: base_url,
        listeners: listeners,
        throttle_ms: throttle_ms
      )

    {module, pid}
  end

  defp start_scraper_instance({module, pid}, %TC.State{}) when is_pid(pid) do
    {module, pid}
  end
end
