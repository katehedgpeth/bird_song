defmodule BirdSong.TestHelpers do
  require Logger
  alias BirdSong.Bird

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
  def start_cache(name \\ Ecto.UUID.generate() |> String.to_atom(), module)
      when is_atom(module) do
    ExUnit.Callbacks.start_supervised({module, name: name})
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
end
