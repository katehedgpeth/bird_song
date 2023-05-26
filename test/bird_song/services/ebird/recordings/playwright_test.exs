defmodule BirdSong.Services.MacaulayLibrary.PlaywrightTest do
  use BirdSong.SupervisedCase, async: true
  use BirdSong.DataCase
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]

  alias BirdSong.{
    Bird,
    Data.Scraper.TimeoutError,
    Data.Scraper.BadResponseError,
    MockMacaulayServer,
    Services.MacaulayLibrary,
    Services.MacaulayLibrary.Playwright,
    Services.ThrottledCache,
    Services.Worker
  }

  @moduletag :capture_log
  @moduletag :slow_test

  @timeout_ms :bird_song
              |> Application.compile_env!(Playwright)
              |> Keyword.fetch!(:default_timeout)

  @throttle_ms :bird_song
               |> Application.compile_env!(ThrottledCache)
               |> Keyword.fetch!(:throttle_ms)

  setup [:seed_from_mock_taxonomy]

  setup tags do
    assert %{
             bypass: %Bypass{} = bypass,
             mock_url: "" <> mock_url,
             worker: %Worker{} = worker
           } = get_worker_setup(MacaulayLibrary, :Playwright, tags)

    unless tags[:expect_request?] === false do
      MockMacaulayServer.setup(tags)
    end

    {:ok, %Bird{species_code: code}} = Bird.get_by_sci_name("Sialia sialis")

    {:ok,
     [
       bypass: bypass,
       base_url: mock_url,
       worker: worker,
       request: %HTTPoison.Request{
         url: Path.join(mock_url, "api/v2/search"),
         params: %{"taxonCode" => code}
       }
     ]}
  end

  describe "open_port" do
    @describetag expect_api_call?: false
    setup tags do
      {:ok, state: %Playwright{base_url: URI.new!(tags[:base_url]), throttle_ms: 0}}
    end

    @tag :slow_test
    test "opens a port", %{state: state} do
      state = Playwright.open_port___test(state)
      assert %Playwright{port: port, ready?: false} = state
      assert is_port(port)
      assert_receive {^port, message}, 2_000
      assert message === {:data, "message=ready_for_requests\n"}

      assert {:noreply, new_state} = Playwright.handle_info({port, message}, state)
      assert %Playwright{ready?: true} = new_state
    end
  end

  describe "MacaulayLibrary.Playwright.run/1 - success response" do
    test "opens a port and returns a response", tags do
      assert %{
               request: request,
               worker: worker
             } = Map.take(tags, [:request, :worker])

      assert %HTTPoison.Request{params: %{"taxonCode" => species_code}} = request

      response = Playwright.run(worker, request)

      assert %{port: port} = GenServer.call(worker.instance_name, :state)
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

    @tag :slow_test
    @tag opts: [{MacaulayLibrary, [throttle_ms: 75]}]
    test "sends 3 throttled requests", tags do
      assert %{request: request, worker: %Worker{} = worker} = Map.take(tags, [:request, :worker])

      Playwright.register_listener(worker)

      state = GenServer.call(worker.instance_name, :state)
      assert state.throttle_ms === 75

      Playwright.run(worker, request)

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

  describe "handle_continue({:open_port, Mix.Env()})" do
    @describetag state: %Playwright{base_url: %URI{}, throttle_ms: 0}
    @describetag expect_request?: false
    test "does not open the port when env is :test", %{state: state} do
      assert {:noreply, %Playwright{port: nil}} =
               Playwright.handle_continue({:open_port, :test}, state)
    end

    test "does open the port when env is :dev or :prod", %{state: state} do
      assert {:noreply, %Playwright{port: dev}} =
               Playwright.handle_continue({:open_port, :dev}, state)

      assert is_port(dev)

      assert {:noreply, %Playwright{port: prod}} =
               Playwright.handle_continue({:open_port, :prod}, state)

      assert is_port(prod)
    end
  end

  describe "MacaulayLibrary.Playwright.run/1 - error responses" do
    @tag expect_api_call?: false
    @tag expect_login?: false
    @tag list_html_response: &MockMacaulayServer.not_found_response/1
    test "returns an error response without crashing when HTML page returns a bad response",
         tags do
      assert %{
               request: request,
               worker: %Worker{} = worker,
               base_url: base_url
             } = Map.take(tags, [:request, :base_url, :worker])

      assert {:error,
              %BadResponseError{
                response_body: "That page does not exist",
                status: 404,
                url: url
              }} = Playwright.run(worker, request)

      assert url === Path.join(base_url, "/catalog?view=list")

      refute_receive {
        Playwright,
        %DateTime{},
        {:request, %{current_request_number: 1, responses: []}}
      }

      assert %{port: port} = GenServer.call(worker.instance_name, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end

    @tag list_html_response: &MockMacaulayServer.bad_structure_response/1
    @tag expect_api_call?: false
    @tag expect_login?: false
    test "returns an error when sign in link is not found", tags do
      assert %{
               worker: %Worker{} = worker,
               request: request
             } = Map.take(tags, [:worker, :request])

      assert Playwright.run(worker, request) ===
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

      assert %{port: port} = GenServer.call(worker.instance_name, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end

    @tag recordings_response: &MockMacaulayServer.not_authorized_response/1
    test "returns an error response without crashing when API request returns a bad response",
         tags do
      assert %{
               request: request,
               worker: %Worker{} = worker,
               base_url: base_url
             } = Map.take(tags, [:request, :worker, :base_url])

      assert Playwright.run(worker, request, 3_000) === {
               :error,
               %BadResponseError{
                 __exception__: true,
                 response_body: "{\"error\": \"You are not authorized to perform this action\"}",
                 status: 403,
                 url: Path.join(base_url, "/api/v2/search")
               }
             }

      assert %{port: port} = GenServer.call(worker.instance_name, :state)
      assert {:connected, _pid} = Port.info(port, :connected)
    end
  end
end
