defmodule BirdSong.Services.RequestThrottlers.MacaulayLibraryTest do
  use BirdSong.DataCase

  alias BirdSong.{
    Bird,
    MockMacaulayServer,
    Services.Ebird.Recordings.Playwright,
    Services.RequestThrottler,
    Services.RequestThrottler.ForbiddenExternalURLError,
    Services.RequestThrottlers.MacaulayLibrary,
    TestHelpers
  }

  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]

  @throttle_ms 100
  @timeout_ms 1_000

  @moduletag :capture_log

  setup [
    :seed_from_mock_taxonomy,
    :setup_mock_server,
    :start_playwright,
    :start_throttler,
    :get_request
  ]

  test "add_to_queue", %{throttler: throttler, request: request} do
    MacaulayLibrary.add_to_queue(
      request,
      throttler
    )

    assert_receive {:"$gen_cast", %RequestThrottler.Response{response: response}},
                   5_000

    assert {:ok, [%{"ageSex" => _} | _]} = response
  end

  @tag use_mock_server?: false
  test "does not call external URLs if not explicitly allowed", %{
    base_url: base_url,
    request: request,
    throttler: throttler
  } do
    assert :ok = MacaulayLibrary.add_to_queue(%{request | url: "/"}, throttler)

    assert_receive {:"$gen_cast", %RequestThrottler.Response{response: response}},
                   5_000

    assert {:error, %ForbiddenExternalURLError{}} = response
    refute_receive {:"$gen_cast", %RequestThrottler.Response{base_url: ^base_url}}
  end

  defp setup_mock_server(%{use_mock_server?: false}) do
    {:ok, base_url: "https://search.macaulaylibrary.org"}
  end

  defp setup_mock_server(%{} = tags) do
    bypass = Bypass.open()

    tags
    |> Map.put(:bypass, bypass)
    |> MockMacaulayServer.setup()

    {:ok, bypass: bypass, base_url: TestHelpers.mock_url(bypass)}
  end

  defp get_variable_opts(tags) do
    tags
    |> Map.take([:base_url, :allow_external_calls?])
    |> Keyword.new()
  end

  defp get_request(%{}) do
    {:ok, %Bird{species_code: code}} = Bird.get_by_sci_name("Sialia sialis")

    {:ok,
     request: %HTTPoison.Request{
       url: "/api/v2/search",
       params: %{"taxonCode" => code}
     }}
  end

  defp start_playwright(%{} = tags) do
    {:ok, playwright} =
      tags
      |> get_variable_opts()
      |> Keyword.merge(
        listeners: [],
        throttle_ms: @throttle_ms,
        timeout: @timeout_ms
      )
      |> Playwright.start_link()

    {:ok, playwright: playwright}
  end

  defp start_throttler(%{} = tags) do
    {:ok, throttler} =
      tags
      |> get_variable_opts()
      |> Keyword.merge(
        throttle_ms: @throttle_ms,
        scraper: {Playwright, tags[:playwright]}
      )
      |> MacaulayLibrary.start_link()

    {:ok, throttler: throttler}
  end
end
