defmodule BirdSong.Services.RequestThrottlerTest.ThrottledCache1 do
  use BirdSong.ThrottledCacheUnderTest, ets_name: :throttled_cache_1, ets_opts: []
end

defmodule BirdSong.Services.RequestThrottlerTest.ThrottledCache2 do
  use BirdSong.ThrottledCacheUnderTest, ets_name: :throttled_cache_2, ets_opts: []
end

defmodule BirdSong.Services.RequestThrottlerTest do
  use ExUnit.Case, async: true

  alias BirdSong.Services.RequestThrottler.ForbiddenExternalURLError

  alias BirdSong.{
    Services.RequestThrottler,
    Services.RequestThrottler.Response,
    Services.Service,
    Services.ThrottledCache,
    TestHelpers
  }

  alias __MODULE__.{ThrottledCache1, ThrottledCache2}

  @moduletag :tmp_dir

  @throttle_ms 200

  setup [:setup_throttler]

  defp setup_throttler(%{skip_setup: true}) do
    :ok
  end

  defp setup_throttler(%{}) do
    bypass = Bypass.open()
    Bypass.expect(bypass, &mock_response/1)

    {:ok, throttler_pid} =
      RequestThrottler.start_link(
        base_url: TestHelpers.mock_url(bypass),
        throttle_ms: @throttle_ms
      )

    {:ok, throttler_pid: throttler_pid, bypass: bypass}
  end

  describe "external_urls" do
  end

  describe "&add_to_queue/1" do
    test "sends a request immediately if the queue is empty", %{throttler_pid: pid} do
      request = %HTTPoison.Request{url: "/success/1"}

      assert RequestThrottler.add_to_queue(request, pid) === :ok

      assert_receive {:"$gen_cast", %Response{response: response, timers: timers}},
                     @throttle_ms + 20

      assert response === {:ok, %{"message" => "success", "request" => 1}}
      assert %{queued: %NaiveDateTime{}, responded: %NaiveDateTime{}} = timers
    end

    test "throttles requests", %{throttler_pid: pid} do
      1..5
      |> Enum.map(&%HTTPoison.Request{url: "/success/#{&1}"})
      |> Enum.map(&RequestThrottler.add_to_queue(&1, pid))

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, %{"request" => 1}}, timers: timers_1}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, %{"request" => 2}}, timers: timers_2}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, %{"request" => 3}}, timers: timers_3}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, %{"request" => 4}}, timers: timers_4}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast",
                      %Response{response: {:ok, %{"request" => 5}}, timers: timers_5}},
                     @throttle_ms + 100

      assert NaiveDateTime.diff(timers_1[:sent], timers_1[:queued], :millisecond) < @throttle_ms

      assert throttled_time(timers_1, timers_2) >= @throttle_ms
      assert throttled_time(timers_2, timers_3) >= @throttle_ms
      assert throttled_time(timers_3, timers_4) >= @throttle_ms
      assert throttled_time(timers_4, timers_5) >= @throttle_ms
    end

    test "works with more than 1 ThrottledCache at a time", %{
      bypass: bypass,
      tmp_dir: tmp_dir,
      throttler_pid: throttler_pid
    } do
      base_url = TestHelpers.mock_url(bypass)

      {:ok, tc_1_pid} =
        ThrottledCache1.start_link(
          base_url: base_url,
          data_folder_path: Path.join(tmp_dir, "tc_1"),
          name: ThrottledCache1,
          throttler: throttler_pid
        )

      tc_1 = %Service{module: ThrottledCache1, whereis: tc_1_pid}

      {:ok, tc_2_pid} =
        ThrottledCache2.start_link(
          base_url: base_url,
          data_folder_path: Path.join(tmp_dir, "tc_2"),
          name: ThrottledCache2,
          throttler: throttler_pid
        )

      tc_2 = %Service{module: ThrottledCache2, whereis: tc_2_pid}

      calls = [
        {ThrottledCache1, "tc1_call_1", tc_1},
        {ThrottledCache2, "tc2_call_1", tc_2},
        {ThrottledCache1, "tc1_call_2", tc_1},
        {ThrottledCache2, "tc2_call_2", tc_2},
        {ThrottledCache1, "tc1_call_3", tc_1},
        {ThrottledCache2, "tc2_call_3", tc_2}
      ]

      responses =
        calls
        |> Enum.map(fn {module, arg, service} ->
          {module, :get, [{module, arg}, service]}
        end)
        |> Task.async_stream(fn {m, f, a} -> apply(m, f, a) end)
        |> Enum.into([])
        |> Enum.map(fn {:ok, response} -> response end)

      [{"User-Agent", user_agent}] = ThrottledCache.user_agent()

      expected_responses =
        Enum.map(calls, fn {module, arg, %Service{}} ->
          {:ok,
           module
           |> Module.concat(:Response)
           |> struct(
             response: %{
               "endpoint" => "endpoint/" <> arg,
               "headers" => %{
                 "host" => "localhost:#{bypass.port}",
                 "user-agent" => user_agent,
                 "x-custom-header" => arg
               },
               "query_params" => %{"param" => arg}
             }
           )}
        end)

      assert Enum.at(expected_responses, 0) ===
               {:ok,
                %ThrottledCache1.Response{
                  response: %{
                    "endpoint" => "endpoint/tc1_call_1",
                    "headers" => %{
                      "host" => "localhost:#{bypass.port}",
                      "user-agent" => user_agent,
                      "x-custom-header" => "tc1_call_1"
                    },
                    "query_params" => %{"param" => "tc1_call_1"}
                  }
                }}

      assert responses === expected_responses
    end
  end

  describe "&add_to_queue/1 with external base_url" do
    @describetag :skip_setup
    @describetag external_url: "https://google.com"

    test "returns an error when external url is not expressly allowed in tests", %{
      external_url: external_url
    } do
      assert {:ok, pid} = RequestThrottler.start_link(base_url: external_url)
      request = %HTTPoison.Request{url: "/aisdflasdjflsj"}

      RequestThrottler.add_to_queue(request, pid)

      expected_error = ForbiddenExternalURLError.exception(opts: [base_url: external_url])

      assert_receive {:"$gen_cast",
                      %Response{
                        base_url: {:error, ^expected_error},
                        response: {:error, ^expected_error}
                      }}
    end

    @tag :not_mocked
    test "calls external URL if external urls are explicitly allowed", %{
      external_url: external_url
    } do
      assert {:ok, pid} =
               RequestThrottler.start_link(
                 base_url: external_url,
                 allow_external_calls?: true
               )

      request = %HTTPoison.Request{url: "/aisdflasdjflsj"}

      RequestThrottler.add_to_queue(request, pid)

      {:ok, log} =
        ExUnit.CaptureLog.with_log(fn ->
          unexpected_error = ForbiddenExternalURLError.exception(opts: [base_url: external_url])
          full_path = "#{external_url}/aisdflasdjflsj"

          assert_receive {:"$gen_cast",
                          %Response{
                            base_url: ^external_url,
                            response: {:error, {:not_found, ^full_path}}
                          }},
                         5_000

          refute_receive {:"$gen_cast",
                          %Response{
                            base_url: {:error, ^unexpected_error},
                            response: {:error, ^unexpected_error}
                          }}

          :ok
        end)

      assert log =~ ~s(event="external_api_call")
    end
  end

  defp throttled_time(%{responded: responded}, %{sent: sent}) do
    NaiveDateTime.diff(sent, responded, :millisecond)
  end

  defp mock_response(%Plug.Conn{path_info: ["success", request]} = conn) do
    Plug.Conn.resp(
      conn,
      200,
      Jason.encode!(%{message: "success", request: String.to_integer(request)})
    )
  end

  defp mock_response(
         %Plug.Conn{
           query_params: query_params,
           req_headers: headers,
           path_info:
             [
               "endpoint",
               "tc" <> <<_::binary-size(1)>> <> "_call_" <> <<_::binary-size(1)>>
             ] = path
         } = conn
       ) do
    Plug.Conn.resp(
      conn,
      200,
      Jason.encode!(%{
        endpoint: Path.join(path),
        headers: Enum.into(headers, %{}),
        query_params: query_params
      })
    )
  end
end
