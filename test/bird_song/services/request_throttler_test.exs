defmodule BirdSong.Services.RequestThrottlerTest do
  use ExUnit.Case, async: true
  alias BirdSong.TestHelpers
  alias BirdSong.Services.RequestThrottler

  @throttle_ms 200

  setup do
    bypass = Bypass.open()
    Bypass.expect(bypass, &mock_response/1)

    {:ok, pid} =
      RequestThrottler.start_link(
        base_url: TestHelpers.mock_url(bypass),
        throttle_ms: @throttle_ms
      )

    {:ok, pid: pid, bypass: bypass}
  end

  describe "&add_to_queue/1" do
    test "sends a request immediately if the queue is empty", %{pid: pid} do
      request = %HTTPoison.Request{url: "/success/1"}

      assert RequestThrottler.add_to_queue(request, pid) === :ok
      assert_receive {:"$gen_cast", {:response, response, timers}}, @throttle_ms
      assert response === {:ok, %{"message" => "success", "request" => 1}}
      assert %{queued: %NaiveDateTime{}, responded: %NaiveDateTime{}} = timers
    end

    test "throttles requests", %{pid: pid} do
      1..5
      |> Enum.map(&%HTTPoison.Request{url: "/success/#{&1}"})
      |> Enum.map(&RequestThrottler.add_to_queue(&1, pid))

      assert_receive {:"$gen_cast", {:response, {:ok, %{"request" => 1}}, timers_1}}, 200

      assert_receive {:"$gen_cast", {:response, {:ok, %{"request" => 2}}, timers_2}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast", {:response, {:ok, %{"request" => 3}}, timers_3}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast", {:response, {:ok, %{"request" => 4}}, timers_4}},
                     @throttle_ms + 100

      assert_receive {:"$gen_cast", {:response, {:ok, %{"request" => 5}}, timers_5}},
                     @throttle_ms + 100

      assert NaiveDateTime.diff(timers_1[:sent], timers_1[:queued], :millisecond) < @throttle_ms

      assert throttled_time(timers_1, timers_2) >= @throttle_ms
      assert throttled_time(timers_2, timers_3) >= @throttle_ms
      assert throttled_time(timers_3, timers_4) >= @throttle_ms
      assert throttled_time(timers_4, timers_5) >= @throttle_ms
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
end
