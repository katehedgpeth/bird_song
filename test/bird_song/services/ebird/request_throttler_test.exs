defmodule BirdSong.Services.Ebird.RequestThrottlerTest do
  use BirdSong.SupervisedCase, use_db?: true
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    MockEbirdServer,
    Services.Ebird.RequestThrottler,
    Services.RequestThrottler.Response,
    Services.Supervisor.ForbiddenExternalURLError,
    Services.Worker
  }

  @throttle_ms 200

  @moduletag :tmp_dir
  @moduletag opts: [throttle_ms: @throttle_ms]

  setup_all do
    {:ok, mock_observations: File.read!("test/mock_data/recent_observations.json")}
  end

  setup tags do
    {:ok, get_worker_setup(Ebird, :RequestThrottler, tags)}
  end

  describe "&add_to_queue/1" do
    setup tags do
      MockEbirdServer.setup(tags)
    end

    test "sends a request immediately if the queue is empty", tags do
      assert %{worker: worker} = Map.take(tags, [:worker])

      request = Ebird.Regions.build_request({:regions, level: :subnational1, parent: "JM"})

      assert RequestThrottler.add_to_queue(request, worker) === :ok

      assert_receive {:"$gen_cast", %Response{response: response, timers: timers}},
                     @throttle_ms + 20

      assert {:ok, [%{"code" => _} | _]} = response
      assert %{queued: %NaiveDateTime{}, responded: %NaiveDateTime{}} = timers
    end
  end

  describe "with external url" do
    @describetag use_bypass?: false
    @describetag request:
                   Ebird.Regions.build_request({:regions, level: :subnational1, parent: "UA"})

    @tag opts: [base_urls: [{Ebird, "https://google.com"}]]
    test "returns an error when external url is not expressly allowed in tests", %{
      worker: throttler,
      request: request
    } do
      assert %Ebird.RequestThrottler{
               base_url: base_url
             } = Worker.call(throttler, :state)

      assert {
               :error,
               %ForbiddenExternalURLError{} = expected_error
             } = base_url

      assert Keyword.fetch!(expected_error.opts, :base_url) == "https://google.com"

      RequestThrottler.add_to_queue(request, throttler)

      assert_receive {:"$gen_cast",
                      %Response{
                        base_url: {:error, ^expected_error},
                        response: {:error, ^expected_error}
                      }}
    end

    @tag opts: [allow_external_calls?: true, base_urls: [{Ebird, "https://google.com"}]]
    @tag :not_mocked
    test "calls external URL if external urls are explicitly allowed", %{
      worker: throttler,
      request: request
    } do
      assert %Ebird.RequestThrottler{base_url: %URI{host: "google.com"}} =
               Worker.call(throttler, :state)

      RequestThrottler.add_to_queue(request, throttler)

      {:ok, log} =
        ExUnit.CaptureLog.with_log(fn ->
          assert_receive {:"$gen_cast",
                          %Response{
                            base_url: "https://google.com",
                            response: {:error, {:not_found, _}}
                          }},
                         5_000

          :ok
        end)

      assert log =~ ~s(event="external_api_call")
    end
  end
end
