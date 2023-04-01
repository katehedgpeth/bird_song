defmodule BirdSong.Services.Ebird.Recordings do
  use BirdSong.Services.ThrottledCache,
    data_folder_path: "data/recordings/ebird",
    ets_opts: [],
    ets_name: :ebird_recordings,
    base_url: "https://search.macaulaylibrary.org",
    scraper: __MODULE__.Playwright

  alias BirdSong.Services.Ebird.Recordings.BadResponseError

  alias BirdSong.{
    Bird,
    Services.Helpers
  }

  alias __MODULE__.{
    Response,
    Playwright
  }

  alias BirdSong.Services.ThrottledCache, as: TC

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
        %TC.State{} = state
      ) do
    [scraper: scraper_module, server: server] =
      state
      |> Map.fetch!(:scraper)
      |> get_scraper_instance(bird, state)

    response = scraper_module.run(server)
    DynamicSupervisor.terminate_child(Services.GenServers, server)

    case response do
      {:ok, [_ | _] = raw_recordings} -> {:ok, Response.parse(raw_recordings)}
      {:error, error} -> {:error, error}
    end
  end

  defp get_scraper_instance(Playwright, %Bird{} = bird, %TC.State{
         base_url: base_url,
         request_listeners: listeners
       }) do
    {:ok, server} =
      DynamicSupervisor.start_child(
        Services.GenServers,
        {Playwright, base_url: base_url, bird: bird, listeners: [self() | listeners]}
      )

    [scraper: Playwright, server: server]
  end

  defp get_scraper_instance(pid, %Bird{}, %TC.State{}) when is_pid(pid) do
    [scraper: GenServer.call(pid, :module), server: pid]
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(msg, from, state) do
    super(msg, from, state)
  end

  def handle_info({:update_scraper_instance, pid}, state) do
    {:noreply, Map.replace!(state, :scraper, pid)}
  end

  def handle_info({ref, {:error, %BadResponseError{status: 404, url: url}}}, state)
      when is_reference(ref) do
    super({ref, {:error, {:not_found, url}}}, state)
  end

  def handle_info({ref, {:error, %BadResponseError{} = error}}, state) when is_reference(ref) do
    super({ref, {:error, {:bad_response, error}}}, state)
  end

  def handle_info(msg, state) do
    super(msg, state)
  end
end
