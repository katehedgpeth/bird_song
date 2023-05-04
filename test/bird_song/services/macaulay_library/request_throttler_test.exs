defmodule BirdSong.Services.MacaulayLibrary.RequestThrottlerTest do
  use BirdSong.SupervisedCase, async: true

  alias BirdSong.{
    MockMacaulayServer,
    Services.MacaulayLibrary,
    Services.RequestThrottler.Response,
    Services.Supervisor.ForbiddenExternalURLError,
    Services.Worker
  }

  @moduletag :capture_log
  @moduletag service: :MacaulayLibrary

  setup [:get_request]

  setup tags do
    case tags do
      %{start_services?: false} ->
        :ok

      %{} ->
        MockMacaulayServer.setup(tags)

        {:ok,
         Enum.map(
           [:RequestThrottler, :Playwright],
           &{&1, get_worker(MacaulayLibrary, &1, tags)}
         )}
    end
  end

  @tag :slow
  test "add_to_queue", %{request: request, RequestThrottler: throttler} do
    assert %Worker{} = throttler

    assert Worker.call(throttler, :base_url) =~ "http://localhost"

    MacaulayLibrary.RequestThrottler.add_to_queue(request, throttler)

    assert_receive {:"$gen_cast", %Response{response: response}},
                   5_000

    assert {:ok, [%{"ageSex" => _} | _]} = response
  end

  @tag use_bypass?: false
  test "does not call external URLs if not explicitly allowed", tags do
    assert %{RequestThrottler: throttler, request: request} =
             Map.take(tags, [:RequestThrottler, :request])

    assert {:error, %ForbiddenExternalURLError{}} =
             MacaulayLibrary.RequestThrottler.base_url(throttler)

    assert :ok =
             MacaulayLibrary.RequestThrottler.add_to_queue(
               %{request | url: "/"},
               throttler
             )

    assert_receive {:"$gen_cast", %Response{response: response}},
                   5_000

    assert {:error, %ForbiddenExternalURLError{}} = response
    refute_receive {:"$gen_cast", %Response{base_url: "" <> _}}
  end

  defp get_request(%{}) do
    {:ok,
     request: %HTTPoison.Request{
       url: "/api/v2/search",
       params: %{"taxonCode" => "easblu"}
     }}
  end
end
