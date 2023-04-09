defmodule BirdSong.Services.RequestThrottlers.MacaulayLibraryTest do
  use BirdSong.DataCase

  alias BirdSong.{
    Bird,
    MockEbirdServer,
    Services.Ebird.Recordings.Playwright,
    Services.RequestThrottler,
    Services.RequestThrottlers.MacaulayLibrary,
    TestHelpers
  }

  import BirdSong.TestSetup

  @throttle_ms 100
  @timeout_ms 1_000

  setup [:seed_from_mock_taxonomy, :setup_bypass]

  setup tags do
    bypass = Map.fetch!(tags, :bypass)
    MockEbirdServer.setup(tags)
    base_url = TestHelpers.mock_url(bypass)
    {:ok, %Bird{species_code: code}} = Bird.get_by_sci_name("Sialia sialis")

    request = %HTTPoison.Request{
      url: "/api/v2/search",
      params: %{"taxonCode" => code}
    }

    {:ok, playwright} =
      Playwright.start_link(
        base_url: base_url,
        listeners: [],
        throttle_ms: @throttle_ms,
        timeout: @timeout_ms
      )

    {:ok, throttler} =
      MacaulayLibrary.start_link(
        base_url: base_url,
        throttle_ms: @throttle_ms,
        scraper: {Playwright, playwright}
      )

    {:ok,
     bypass: bypass, code: code, playwright: playwright, request: request, throttler: throttler}
  end

  test "add_to_queue", %{throttler: throttler, request: request} do
    MacaulayLibrary.add_to_queue(
      request,
      throttler
    )

    assert_receive {:"$gen_cast", %RequestThrottler.Response{response: response}},
                   5_000

    assert {:ok, [%{"ageSex" => _} | _]} = response
  end
end
