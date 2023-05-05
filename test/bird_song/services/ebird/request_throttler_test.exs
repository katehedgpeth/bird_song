defmodule BirdSong.Services.Ebird.RequestThrottlerTest do
  use BirdSong.SupervisedCase, async: true
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    MockEbirdServer,
    Services,
    Services.Ebird,
    Services.Ebird.RequestThrottler,
    Services.RequestThrottler.Response,
    Services.Supervisor.ForbiddenExternalURLError,
    Services.ThrottledCache,
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

      request = Ebird.Regions.build_request({:regions, level: :subnational1, parent: "UA"})

      assert RequestThrottler.add_to_queue(request, worker) === :ok

      assert_receive {:"$gen_cast", %Response{response: response, timers: timers}},
                     @throttle_ms + 20

      assert {:ok, [%{"code" => _} | _]} = response
      assert %{queued: %NaiveDateTime{}, responded: %NaiveDateTime{}} = timers
    end

    @tag :flaky
    test "throttles requests", %{worker: worker} do
      assert %RequestThrottler{throttle_ms: throttle_ms} = Worker.call(worker, :state)

      assert throttle_ms === @throttle_ms

      countries = ["IL", "AG", "GB", "BG"]

      countries
      |> Enum.map(&Ebird.Regions.build_request({:regions, level: :subnational1, parent: &1}))
      |> Enum.map(&RequestThrottler.add_to_queue(&1, worker))

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, [%{"code" => "IL-" <> _} | _]}, timers: timer_1}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, [%{"code" => "AG-" <> _} | _]}, timers: timer_2}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, [%{"code" => "GB-" <> _} | _]}, timers: timer_3}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, [%{"code" => "BG-" <> _} | _]}, timers: timer_4}},
                     @throttle_ms + 100

      assert NaiveDateTime.diff(timer_1[:sent], timer_1[:queued], :millisecond) < @throttle_ms

      assert throttled_time(timer_1, timer_2) >= @throttle_ms
      assert throttled_time(timer_2, timer_3) >= @throttle_ms
      assert throttled_time(timer_3, timer_4) >= @throttle_ms
    end

    @tag listen_to: [{Ebird, :Observations}, {Ebird, :Regions}]
    test "works with more than 1 ThrottledCache at a time", tags do
      regions_worker = get_worker(Ebird, :Regions, tags)
      observations_worker = get_worker(Ebird, :Observations, tags)
      region_ets_worker = get_worker(Ebird, :RegionETS, tags)

      assert %ThrottledCache.State{listeners: listeners} = Worker.call(regions_worker, :state)
      assert listeners === [self()]

      countries = ["IL", "AG", "GB", "BG"]

      requests =
        countries
        |> Enum.map(&Ebird.RegionETS.get!(&1, region_ets_worker))
        |> Enum.map(
          &[
            {Ebird.Regions, :get_subregions, [&1, regions_worker, :subnational1]},
            {Ebird.Observations, :get_recent_observations, [&1.code, observations_worker]}
          ]
        )
        |> List.flatten()

      assert [
               {Ebird.Regions, _, [%Ebird.Region{code: "IL"} | _]},
               {Ebird.Observations, _, ["IL" | _]},
               {Ebird.Regions, _, [%Ebird.Region{code: "AG"} | _]},
               {Ebird.Observations, _, ["AG" | _]},
               {Ebird.Regions, _, [%Ebird.Region{code: "GB"} | _]},
               {Ebird.Observations, _, ["GB" | _]},
               {Ebird.Regions, _, [%Ebird.Region{code: "BG"} | _]},
               {Ebird.Observations, _, ["BG" | _]}
             ] = requests

      responses =
        requests
        |> Task.async_stream(fn {m, f, a} -> apply(m, f, a) end)
        |> Enum.into([])
        |> Enum.map(fn {:ok, {:ok, response}} -> response end)
        |> Enum.map(fn
          [%Ebird.Region{code: code} | _] -> {:Regions, String.slice(code, 0..1)}
          %Ebird.Observations.Response{region: region} -> {:Observations, region}
        end)

      assert [
               {:Regions, "IL"},
               {:Observations, "IL"},
               {:Regions, "AG"},
               {:Observations, "AG"},
               {:Regions, "GB"},
               {:Observations, "GB"},
               {:Regions, "BG"},
               {:Observations, "BG"}
             ] = responses

      assert [
               {_, _, first},
               {_, _, second},
               {_, _, third},
               {_, _, fourth},
               {_, _, fifth},
               {_, _, sixth},
               {_, _, seventh},
               {_, _, eighth}
             ] =
               requests
               |> Enum.map(fn
                 {Ebird.Regions, _, [%Ebird.Region{code: code} | _]} ->
                   assert_receive {:end_request, %{parent: ^code, response: response}}
                   {Ebird.Regions, code, response}

                 {Ebird.Observations, _, ["" <> code | _]} ->
                   assert_receive {:end_request, %{region: ^code, response: response}}
                   {Ebird.Observations, code, response}
               end)
               |> Enum.map(fn {mod, code, %Services.RequestThrottler.Response{timers: timers}} ->
                 {mod, code, timers[:sent]}
               end)
               |> Enum.sort_by(fn {_m, _c, timer} -> timer end, NaiveDateTime)

      first_before_second = :lt

      assert NaiveDateTime.compare(first, second) === first_before_second

      for diff <- [
            NaiveDateTime.diff(second, first, :millisecond),
            NaiveDateTime.diff(third, second, :millisecond),
            NaiveDateTime.diff(fourth, third, :millisecond),
            NaiveDateTime.diff(fifth, fourth, :millisecond),
            NaiveDateTime.diff(sixth, fifth, :millisecond),
            NaiveDateTime.diff(seventh, sixth, :millisecond),
            NaiveDateTime.diff(eighth, seventh, :millisecond)
          ] do
        assert diff > @throttle_ms
        assert diff < @throttle_ms + 100
      end
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

      assert {:error,
              %ForbiddenExternalURLError{opts: [{:base_url, "https://google.com"} | _]} =
                expected_error} = base_url

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

  defp throttled_time(%{responded: responded}, %{sent: sent}) do
    NaiveDateTime.diff(sent, responded, :millisecond)
  end
end
