defmodule BirdSong.TestHelpers do
  require Logger

  alias BirdSong.Services.MacaulayLibrary

  alias BirdSong.{
    Bird,
    Data.Scraper.BadResponseError,
    MockJsScraper,
    Services,
    Services.MacaulayLibrary,
    Services.Service
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

  @spec start_cache(atom) :: pid
  def start_cache(opts \\ [name: Ecto.UUID.generate() |> String.to_atom()], module)
      when is_atom(module) and is_list(opts) do
    ExUnit.Callbacks.start_supervised!({module, opts})
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

  def start_service_supervised(_module, %{}) do
    raise BirdSong.DeprecatedFunctionError.exception(
            deprecated: "TestHelpers.start_service_supervised/2",
            replacement: "use BirdSong.SupervisedCase"
          )
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

  def get_base_url(opts, %{bypass: %Bypass{} = bypass}) do
    Keyword.put(opts, :base_url, mock_url(bypass))
  end

  def get_base_url(opts, %{}) when is_list(opts) do
    raise "Bypass must be initialized in order to use services in tests"
  end
end
