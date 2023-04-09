defmodule BirdSong.TestHelpers do
  require Logger

  alias BirdSong.{
    Bird,
    Data.Scraper.BadResponseError,
    MockJsScraper,
    Services,
    Services.Service,
    Services.Ebird
  }

  alias Phoenix.LiveView.Socket
  import ExUnit.Assertions, only: [assert: 1, assert: 2]

  def update_env(service, key, new_value) do
    updated =
      :bird_song
      |> Application.fetch_env!(service)
      |> Keyword.put(key, new_value)

    Application.put_env(
      :bird_song,
      service,
      updated
    )
  end

  @spec start_cache(atom) ::
          {:error, any} | {:ok, :undefined | pid} | {:ok, :undefined | pid, any}
  def start_cache(opts \\ [name: Ecto.UUID.generate() |> String.to_atom()], module)
      when is_atom(module) and is_list(opts) do
    ExUnit.Callbacks.start_supervised({module, opts})
  end

  def parse_logs("" <> logs) do
    log_start_regex = ~r/\e\[\d\dm/

    log_start_regex
    |> Regex.split(logs, trim: true)
    |> Enum.map(
      &(log_start_regex
        |> Regex.replace(&1, "", trim: true)
        |> String.replace("\n\e[0m", ""))
    )
  end

  def mock_file_name(%Bird{common_name: common_name}) do
    mock_file_name(common_name)
  end

  def mock_file_name("" <> common_name) do
    common_name
    |> String.replace(" ", "_")
    |> Kernel.<>(".json")
  end

  def mock_file_path("" <> name) do
    "test/mock_data/"
    |> Path.join(mock_file_name(name))
    |> Path.relative_to_cwd()
  end

  def read_mock_file("" <> name) do
    name
    |> mock_file_path()
    |> File.read!()
  end

  def assert_assigned({:noreply, %Socket{} = socket}, key, func) do
    {:noreply, assert_assigned(socket, key, func)}
  end

  def assert_assigned(%Socket{} = socket, key, func) when is_function(func) do
    socket
    |> get_assigned(key)
    |> func.()

    socket
  end

  def assert_assigned(%Socket{} = socket, key, match) do
    socket
    |> get_assigned(key)
    |> do_assert_assigned(match)

    socket
  end

  defp do_assert_assigned(value, match) when value === match, do: :ok

  defp do_assert_assigned(value, match) do
    assert(^match = value, "expected #{inspect(value)} to match #{inspect(match)}")
  end

  def get_assigned({:noreply, %Socket{} = socket}, key) do
    get_assigned(socket, key)
  end

  def get_assigned(%Socket{assigns: assigns}, key) do
    Map.fetch!(assigns, key)
  end

  def assert_expected_keys({:noreply, %Socket{} = socket}, expected_keys) do
    {:noreply, assert_expected_keys(socket, expected_keys)}
  end

  def assert_expected_keys(%Socket{} = socket, expected_keys) do
    assert(
      socket
      |> Map.fetch!(:assigns)
      |> Map.keys() === expected_keys
    )

    socket
  end

  def start_service_supervised(module, %{} = tags) do
    {:ok, pid} =
      []
      |> get_base_url(tags)
      |> get_data_folder_path_opt(tags, module)
      |> get_scraper_opt(tags, module)
      |> get_service_name_opt(tags, module)
      |> get_throttler_opt(tags)
      |> get_throttle_ms_opt(tags)
      |> start_cache(module)

    %Service{module: module, whereis: pid}
  end

  def module_alias(module) do
    module
    |> Module.split()
    |> List.last()
  end

  def mock_url(%Bypass{port: port}), do: "http://localhost:#{port}"

  def do_for_services(%Services{} = services, callback) when is_function(callback) do
    for %Service{} = service <- services |> Map.from_struct() |> Map.values() do
      callback.(service)
    end
  end

  defp get_base_url(opts, %{bypass: %Bypass{} = bypass}) do
    Keyword.put(opts, :base_url, mock_url(bypass))
  end

  defp get_base_url([], %{}) do
    raise "Bypass must be initialized in order to use services in tests"
  end

  defp get_data_folder_path_opt(opts, %{tmp_dir: "" <> tmp_dir}, module) do
    subfolder = module |> Service.data_type() |> Atom.to_string()

    Keyword.put(
      opts,
      :data_folder_path,
      Path.join([tmp_dir, subfolder])
    )
  end

  defp get_data_folder_path_opt(opts, %{}, _module) do
    opts
  end

  defp get_scraper_opt(
         opts,
         %{inject_playwright?: true, playwright_response: maybe_response},
         Ebird.Recordings
       ) do
    scraper_module = MockJsScraper
    response = verify_playwright_response_format(maybe_response)
    {:ok, pid} = ExUnit.Callbacks.start_supervised({scraper_module, response: response})
    Keyword.put(opts, :scraper, {scraper_module, pid})
  end

  defp get_scraper_opt(opts, %{scraper: scraper}, Ebird.Recordings) do
    Keyword.put(opts, :scraper, scraper)
  end

  defp get_scraper_opt(opts, %{}, Ebird.Recordings) do
    Logger.warning("using Ebird.Recordings.Playwright for scraper module")
    opts
  end

  defp get_scraper_opt(opts, %{}, _) do
    opts
  end

  defp get_service_name_opt(opts, %{test: test}, module) do
    Keyword.put(opts, :name, Module.concat(test, module_alias(module)))
  end

  defp get_throttler_opt(opts, tags) do
    Keyword.put(
      opts,
      :throttler,
      Map.get(tags, :throttler, :throttler_not_set)
    )
  end

  def get_throttle_ms_opt(opts, %{throttle_ms: throttle_ms}) do
    Keyword.put(opts, :throttle_ms, throttle_ms)
  end

  def get_throttle_ms_opt(opts, %{}), do: opts

  defp verify_playwright_response_format(maybe_response) do
    case maybe_response do
      {:file, "" <> _} ->
        maybe_response

      {:ok, [%{} | _]} ->
        maybe_response

      {:error, %BadResponseError{}} ->
        maybe_response

      _ ->
        raise """
        Invalid playwright response format: #{inspect(maybe_response)}
        """
    end
  end
end
