defmodule BirdSong.MockJsScraper do
  use GenServer
  alias BirdSong.Data.Scraper

  @behaviour Scraper

  @type response_opt :: {:file, String.t()} | Playwright.response()

  def run(server, _) do
    GenServer.call(server, :response)
  end

  def start_instance(response: response) do
    DynamicSupervisor.start_child(
      Services.GenServers,
      {__MODULE__, response: response}
    )
  end

  def stop_instance(pid) do
    DynamicSupervisor.terminate_child(Services.GenServers, pid)
  end

  @spec start_link(response: response_opt) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def init(response: {:file, response_file}) do
    response =
      response_file
      |> File.read!()
      |> Jason.decode!()

    {:ok, response: {:ok, response}}
  end

  def init(response: {:ok, [%{} | _] = data}) do
    {:ok, response: {:ok, data}}
  end

  def init(response: {:error, %{__struct__: struct}} = error)
      when struct in [Scraper.BadResponseError] do
    {:ok, response: error}
  end

  def handle_call(:module, _from, state) do
    {:reply, __MODULE__, state}
  end

  def handle_call(:response, _from, state) do
    {:reply, Keyword.fetch!(state, :response), state}
  end
end
