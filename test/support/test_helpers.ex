defmodule BirdSong.TestHelpers do
  alias BirdSong.Services.Helpers

  @env Mix.env()

  def update_env(service, key, new_value) do
    old_env = Application.fetch_env!(:bird_song, service)
    func = if Keyword.has_key?(old_env, key), do: :replace!, else: :put

    Application.put_env(
      :ebird,
      service,
      apply(Keyword, func, [old_env, key, new_value])
    )
  end

  @spec start_cache(atom) ::
          {:error, any} | {:ok, :undefined | pid} | {:ok, :undefined | pid, any}
  def start_cache(module) when is_atom(module) do
    ExUnit.Callbacks.start_supervised({
      module,
      name: Ecto.UUID.generate() |> String.to_atom()
    })
  end

  def parse_logs("" <> logs) do
    logs
    |> String.split("\e[33m")
    |> Enum.reject(&(&1 === ""))
    |> Enum.map(&String.replace(&1, "\n\e[0m", ""))
  end

  def mock_file_name("" <> name) do
    name
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

  def write_to_disk({:ok, %HTTPoison.Response{body: data} = response}, "" <> name, app)
      when is_atom(app) and @env === :test do
    app
    |> Helpers.get_env(:write_to_disk?)
    |> case do
      true ->
        name
        |> mock_file_path()
        |> File.write!(data)

      false ->
        :ok
    end

    {:ok, response}
  end

  def write_to_disk({:ok, %HTTPoison.Response{} = response}, "" <> _, app) when is_atom(app),
    do: response

  def write_to_disk({:error, error}, "" <> _, app) when is_atom(app), do: {:error, error}
end
