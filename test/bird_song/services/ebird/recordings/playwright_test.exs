defmodule BirdSong.Services.Ebird.Recordings.PlaywrightTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1, setup_bypass: 1]

  alias BirdSong.{
    Bird,
    Data.Scraper.TimeoutError,
    Data.Scraper.BadResponseError,
    MockEbirdServer,
    Services.Ebird.Recordings.Playwright,
    TestHelpers
  }

  @moduletag :capture_log
  @moduletag :slow_test
  @throttle_ms 100
  @timeout_ms 500

  setup [:seed_from_mock_taxonomy, :setup_bypass]

  setup %{bypass: bypass} = tags do
    MockEbirdServer.setup(tags)

    {:ok, bird} = Bird.get_by_sci_name("Sialia sialis")

    {:ok, server} =
      Playwright.start_link(
        base_url: TestHelpers.mock_url(bypass),
        listeners: [self()],
        throttle_ms: @throttle_ms,
        timeout: @timeout_ms
      )

    {:ok, bird: bird, bypass: bypass, server: server}
  end

  defp endpoint(:html), do: "/catalog"
  defp endpoint(:api), do: "/api/v2/search"

  def mock_response(bypass, html_or_api, status_code, body) do
    Bypass.expect(
      bypass,
      "GET",
      endpoint(html_or_api),
      &Plug.Conn.resp(&1, status_code, body)
    )
  end

  def do_not_expect_api_response(bypass) do
    Bypass.stub(
      bypass,
      "GET",
      endpoint(:api),
      &Plug.Conn.resp(&1, 500, "this should not have been called")
    )
  end

  describe "Ebird.Recordings.Playwright.run/1 - success response" do
    test "opens a port and returns a response", %{bird: bird, server: server} do
      response = Playwright.run(server, bird)

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

        assert %Bird{species_code: species_code} = bird

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

    test "sends 3 throttled requests", %{bird: bird, server: server} do
      Playwright.run(server, bird)

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

  describe "Ebird.Recordings.Playwright.run/1 - error responses" do
    @tag expect_api_call?: false
    @tag expect_login?: false
    @tag list_html_response: &MockEbirdServer.not_found_response/1
    test "returns an error response without crashing when HTML page returns a bad response", %{
      bird: bird,
      bypass: bypass,
      server: server
    } do
      assert {:error,
              %BadResponseError{
                response_body: "That page does not exist",
                status: 404,
                url: url
              }} = Playwright.run(server, bird)

      assert url === bypass |> TestHelpers.mock_url() |> Path.join("/catalog?view=list")

      refute_receive {
        Playwright,
        %DateTime{},
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert %{port: port} = GenServer.call(server, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end

    @tag list_html_response: &MockEbirdServer.bad_structure_response/1
    @tag expect_api_call?: false
    @tag expect_login?: false
    test "returns an error when sign in link is not found", %{
      bird: bird,
      server: server
    } do
      assert Playwright.run(server, bird) ===
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

    @tag recordings_response: &MockEbirdServer.not_authorized_response/1
    test "returns an error response without crashing when API request returns a bad response", %{
      bird: bird,
      bypass: bypass,
      server: server
    } do
      assert Playwright.run(server, bird, 3_000) === {
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
