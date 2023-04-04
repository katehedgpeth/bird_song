defmodule BirdSongWeb.QuizLive.MessageHandlersTest do
  use BirdSong.MockApiCase, use_data_case: false
  use BirdSongWeb.LiveCase

  @moduletag services: [:ebird, :xeno_canto]
  @moduletag :capture_log
  @moduletag task_timeout: 1_000

  @region "US-NC-067"

  alias Phoenix.{LiveView, LiveView.Socket}

  alias BirdSongWeb.QuizLive.MessageHandlers

  alias BirdSong.{
    Bird,
    Quiz,
    Services.Ebird,
    Services.XenoCanto
  }

  setup %{services: services, conn: conn, task_timeout: task_timeout} do
    {:ok, %{pid: pid}, _html} = live(conn, "/quiz")

    {:ok,
     pid: pid,
     socket:
       pid
       |> GenServer.call(:socket)
       |> LiveView.assign(:services, services)
       |> LiveView.assign(:task_timeout, task_timeout)
       |> LiveView.assign(:quiz, %Quiz{region: @region})}
  end

  describe "handle_info(:get_recent_observations)" do
    setup [:listen_to_services, :seed_from_mock_taxonomy, :call_recent_observations]

    @tag expect: &MockServer.success_response/1
    test "starts a task to fetch recent observations for a region", %{
      socket: %Socket{assigns: assigns}
    } do
      assert_receive {:end_request,
                      %{
                        module: Ebird.Observations,
                        region: @region,
                        response: {:ok, %Ebird.Response{observations: [%Ebird.Observation{} | _]}}
                      }}

      refute_receive {:get_recent_observations, tries: 1}

      birds = Map.fetch!(assigns, :birds)
      assert [%Bird{} | _] = birds

      assert_receive {:start_request, %{module: XenoCanto, bird: %Bird{}}}
      assert_receive {:start_request, %{module: Flickr, bird: %Bird{}}}
    end

    @tag expect: &MockServer.error_response/1
    test "handles a bad response from ebird", %{
      socket: %Socket{assigns: %{flash: flash, birds: birds}}
    } do
      assert_receive {:end_request,
                      %{
                        module: Ebird.Observations,
                        region: @region,
                        response: {:error, error}
                      }}

      assert {:bad_response, %HTTPoison.Response{}} = error

      assert birds === []

      assert %{"error" => ":recent_observations task returned an error: " <> _} = flash
    end

    @tag task_timeout: 5
    @tag use_mock: false
    @tag skip: true
    @tag :use_slow_response
    test "handles a timeout", %{socket: socket, pid: pid} do
      warning_flash = %{
        "warning" => "Getting birds is taking longer than expected..."
      }

      assert Map.fetch!(socket.assigns, :flash) === warning_flash

      for tries <- 1..2 do
        assert_receive {:get_recent_observations, tries: ^tries} = message
        assert {:noreply, %Socket{} = socket} = MessageHandlers.handle_info(message, socket)

        assert Map.fetch!(socket.assigns, :flash) === warning_flash
      end

      assert_receive {:get_recent_observations, tries: 3} = message
      assert {:noreply, %Socket{assigns: assigns}} = MessageHandlers.handle_info(message, socket)

      assert Map.fetch!(assigns, :flash) === %{
               "error" =>
                 "eBird is not responding to our requests at the moment. Please try again later."
             }

      assert GenServer.call(pid, :kill_all_tasks) === []
    end
  end

  def call_recent_observations(%{bypass: bypass, socket: socket} = tags) do
    if Map.get(tags, :use_slow_response) do
      Bypass.stub(bypass, :any, :any, &__MODULE__.slow_response/1)
    end

    assert {:noreply, %Socket{} = socket} =
             MessageHandlers.handle_info(:get_recent_observations, socket)

    assert_receive {:get_recent_observations, tries: 0} = message

    assert {:noreply, %Socket{} = socket} = MessageHandlers.handle_info(message, socket)

    assert_receive {:start_request, %{module: Ebird.Observations, region: @region}}
    {:ok, socket: socket}
  end

  def slow_response(conn) do
    Process.sleep(100)
    MockServer.success_response(conn)
  end
end
