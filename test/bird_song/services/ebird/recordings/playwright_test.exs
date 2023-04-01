defmodule BirdSong.Services.Ebird.Recordings.PlaywrightTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]
  alias BirdSong.TestHelpers

  alias BirdSong.{
    Bird,
    Services.Ebird.Recordings
  }

  alias Recordings.{Playwright, TimeoutError, BadResponseError}

  @throttle_ms 100

  setup_all do
    {:ok,
     mock_data: File.read!("test/mock_data/ebird_recordings.json"),
     mock_html: File.read!("test/mock_data/ebird_recordings.html")}
  end

  setup [:seed_from_mock_taxonomy]

  setup do
    bypass = Bypass.open()
    Bypass.stub(bypass, :any, :any, &Plug.Conn.resp(&1, 500, ""))

    {:ok, bird} = Bird.get_by_sci_name("Sialia sialis")

    {:ok, server} =
      Playwright.start_link(
        bird: bird,
        listeners: [self()],
        throttle_ms: @throttle_ms,
        base_url: TestHelpers.mock_url(bypass)
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
    setup %{bypass: bypass, mock_html: mock_html, mock_data: mock_data} do
      mock_response(bypass, :html, 200, mock_html)
      mock_response(bypass, :api, 200, mock_data)
      :ok
    end

    test "opens a port and returns a response", %{bird: bird, server: server} do
      response = Playwright.run(server)

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

    test "sends 3 throttled requests", %{server: server} do
      Playwright.run(server)

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
    test "returns an error response without crashing when HTML page returns a bad response", %{
      server: server,
      bypass: bypass
    } do
      body_404 = "<div>That page doesn't exist</div>"
      mock_response(bypass, :html, 404, body_404)
      do_not_expect_api_response(bypass)

      assert {:error,
              %BadResponseError{
                response_body: ^body_404,
                status: 404,
                url: url
              }} = Playwright.run(server)

      assert url === bypass |> TestHelpers.mock_url() |> Path.join("/catalog?view=list")

      refute_receive {
        Playwright,
        %DateTime{},
        {:request, %{current_request_number: 1, responses: []}}
      }
    end

    test "returns an error without crashing when .ResponseList is not found", %{
      bypass: bypass,
      server: server
    } do
      mock_response(bypass, :html, 200, "<div>This is an unexpected document structure</div>")
      do_not_expect_api_response(bypass)

      assert Playwright.run(server) ===
               {:error,
                %TimeoutError{
                  js_message:
                    Enum.join(
                      [
                        "Timeout 3000ms exceeded.",
                        "=========================== logs ===========================",
                        "waiting for locator('.ResultsList') to be visible",
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
    end

    test "returns an error response without crashing when API request returns a bad response", %{
      bypass: bypass,
      mock_html: mock_html,
      server: server
    } do
      mock_response(bypass, :html, 200, mock_html)

      mock_response(
        bypass,
        :api,
        403,
        ~s({"error": "You are not authorized to perform this action"})
      )

      assert Playwright.run(server) === {
               :error,
               %BirdSong.Services.Ebird.Recordings.BadResponseError{
                 __exception__: true,
                 response_body: "{\"error\": \"You are not authorized to perform this action\"}",
                 status: 403,
                 url: bypass |> TestHelpers.mock_url() |> Path.join("/api/v2/search")
               }
             }
    end
  end
end
