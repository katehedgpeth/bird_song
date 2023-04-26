defmodule BirdSong.Services.MacaulayLibrary.PlaywrightTest do
  use BirdSong.DataCase, async: true
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1, setup_bypass: 1]

  alias BirdSong.{
    Bird,
    Data.Scraper.TimeoutError,
    Data.Scraper.BadResponseError,
    MockMacaulayServer,
    Services.MacaulayLibrary.Playwright,
    TestHelpers
  }

  @moduletag :capture_log
  @moduletag :slow_test
  @throttle_ms 100
  @timeout_ms 500

  setup [:seed_from_mock_taxonomy, :setup_bypass]

  setup %{bypass: bypass} = tags do
    MockMacaulayServer.setup(tags)
    base_url = TestHelpers.mock_url(bypass)
    {:ok, %Bird{species_code: code}} = Bird.get_by_sci_name("Sialia sialis")

    request = %HTTPoison.Request{
      url: Path.join(base_url, "api/v2/search"),
      params: %{"taxonCode" => code}
    }

    {:ok, server} =
      Playwright.start_link(
        base_url: base_url,
        listeners: [self()],
        throttle_ms: @throttle_ms,
        timeout: @timeout_ms
      )

    {:ok, bypass: bypass, server: server, request: request}
  end

  describe "MacaulayLibrary.Playwright.run/1 - success response" do
    test "opens a port and returns a response", %{request: request, server: server} do
      response = Playwright.run(server, request)

      assert %{port: port} = GenServer.call(server, :state)
      assert {:connected, _pid} = Port.info(port, :connected)

      assert {:ok, data} = response
      assert is_list(data)
      assert length(data) === 90

      for recording <- data do
        assert %{
                 "ageSex" => _,
                 "assetId" => _,
                 "assetState" => _,
                 "cursorMark" => _,
                 "ebirdChecklistId" => _,
                 "exoticCategory" => _,
                 "height" => _,
                 "licenseId" => _,
                 "location" => _,
                 "mediaNotes" => _,
                 "mediaType" => "audio",
                 "obsDt" => _,
                 "obsDtDisplay" => _,
                 "obsMonth" => _,
                 "obsTime" => _,
                 "obsYear" => _,
                 "parentAssetId" => _,
                 "rating" => _,
                 "ratingCount" => _,
                 "restricted" => _,
                 "reviewed" => _,
                 "source" => _,
                 "tags" => _,
                 "taxonomy" => taxonomy,
                 "userDisplayName" => _,
                 "userHasProfile" => _,
                 "userId" => _,
                 "valid" => _,
                 "width" => _
               } = recording

        assert %HTTPoison.Request{params: %{"taxonCode" => species_code}} = request

        assert Map.keys(taxonomy) === [
                 "category",
                 "comName",
                 "reportAs",
                 "sciName",
                 "speciesCode"
               ]

        assert %{
                 "reportAs" => ^species_code
               } = taxonomy
      end
    end

    test "sends 3 throttled requests", %{request: request, server: server} do
      Playwright.run(server, request)

      refute_receive {Playwright, %DateTime{}, {:request, %{current_request_number: 0}}}
      refute_receive {Playwright, %DateTime{}, {:request, %{current_request_number: 4}}}

      assert_receive {
        Playwright,
        %DateTime{} = request_1_time,
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert_receive {
                       Playwright,
                       %DateTime{} = request_2_time,
                       {:request, %{current_request_number: 2, responses: responses}}
                     }
                     when length(responses) === 30

      assert_receive {
                       Playwright,
                       %DateTime{} = request_3_time,
                       {:request, %{current_request_number: 3, responses: responses}}
                     }
                     when length(responses) === 60

      assert DateTime.diff(request_2_time, request_1_time, :millisecond) > @throttle_ms
      assert DateTime.diff(request_3_time, request_2_time, :millisecond) > @throttle_ms
    end
  end

  describe "MacaulayLibrary.Playwright.run/1 - error responses" do
    @tag expect_api_call?: false
    @tag expect_login?: false
    @tag list_html_response: &MockMacaulayServer.not_found_response/1
    test "returns an error response without crashing when HTML page returns a bad response", %{
      bypass: bypass,
      request: request,
      server: server
    } do
      assert {:error,
              %BadResponseError{
                response_body: "That page does not exist",
                status: 404,
                url: url
              }} = Playwright.run(server, request)

      assert url === bypass |> TestHelpers.mock_url() |> Path.join("/catalog?view=list")

      refute_receive {
        Playwright,
        %DateTime{},
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert %{port: port} = GenServer.call(server, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end

    @tag list_html_response: &MockMacaulayServer.bad_structure_response/1
    @tag expect_api_call?: false
    @tag expect_login?: false
    test "returns an error when sign in link is not found", %{
      request: request,
      server: server
    } do
      assert Playwright.run(server, request) ===
               {:error,
                %TimeoutError{
                  timeout_message:
                    Enum.join(
                      [
                        "Timeout #{@timeout_ms}ms exceeded.",
                        "=========================== logs ===========================",
                        "waiting for locator('a.Header-link').getByText('Sign in')",
                        "============================================================"
                      ],
                      "\n"
                    )
                }}

      refute_receive {
        Playwright,
        %DateTime{},
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert %{port: port} = GenServer.call(server, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end

    @tag recordings_response: &MockMacaulayServer.not_authorized_response/1
    test "returns an error response without crashing when API request returns a bad response", %{
      request: request,
      bypass: bypass,
      server: server
    } do
      assert Playwright.run(server, request, 3_000) === {
               :error,
               %BadResponseError{
                 __exception__: true,
                 response_body: "{\"error\": \"You are not authorized to perform this action\"}",
                 status: 403,
                 url: bypass |> TestHelpers.mock_url() |> Path.join("/api/v2/search")
               }
             }

      assert %{port: port} = GenServer.call(server, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end
  end
end
