defmodule BirdSong.Services.MacaulayLibrary.RequestThrottler do
  use BirdSong.Services.RequestThrottler

  alias BirdSong.{
    Services.MacaulayLibrary,
    Services.RequestThrottler
  }

  #########################################################
  #########################################################
  ##
  ##  PUBLIC API
  ##
  #########################################################

  #########################################################
  #########################################################
  ##
  ##  OVERRIDES
  ##
  #########################################################

  @impl RequestThrottler
  def call_endpoint(request, %__MODULE__{worker: worker}) do
    worker
    |> Worker.get_sibling(:Playwright)
    |> MacaulayLibrary.Playwright.run(request)
  end

  @impl RequestThrottler
  def parse_response(response, %__MODULE__{}) do
    response
  end

  #########################################################
  #########################################################
  ##
  ##  GENSERVER
  ##
  #########################################################

  @impl GenServer

  def handle_info(msg, state) do
    super(msg, state)
  end
end
