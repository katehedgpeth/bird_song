defmodule BirdSong.Services.XenoCanto.Cache do
  use GenServer
  alias BirdSong.Services.{Helpers, XenoCanto, XenoCanto.Response}

  @table :xeno_canto

  def get(bird) do
    case :ets.lookup(@table, bird) do
      [{^bird, recording}] ->
        {:ok, recording}

      [] ->
        get_recording_from_api(bird)
    end
  end

  def clear_cache() do
    GenServer.cast(__MODULE__, :clear_cache)
  end

  defp get_recording_from_api(bird) do
    bird
    |> XenoCanto.url()
    |> HTTPoison.get()
    |> Helpers.parse_api_response()
    |> case do
      {:ok, raw} ->
        recording = Response.parse(raw)
        GenServer.cast(__MODULE__, {:save, {bird, recording}})
        {:ok, recording}

      error ->
        error
    end
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    ets_table = :ets.new(@table, [:named_table])
    {:ok, ets_table}
  end

  def handle_cast({:save, {bird, recording}}, ets_table) do
    :ets.insert(ets_table, {bird, recording})
    {:noreply, ets_table}
  end

  def handle_cast(:clear_cache, ets_table) do
    :ets.delete_all_objects(ets_table)
    {:noreply, ets_table}
  end

  # used for saving data for tests
  def write_to_disk({:ok, response}, bird) do
    file_name =
      bird
      |> String.replace(" ", "_")
      |> Kernel.<>(".json")

    "test/mock_data/"
    |> Kernel.<>(file_name)
    |> Path.relative_to_cwd()
    |> File.write!(Jason.encode!(response))

    {:ok, response}
  end

  def write_to_disk(response, _), do: response
end
