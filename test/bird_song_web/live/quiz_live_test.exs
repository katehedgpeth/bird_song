defmodule BirdSongWeb.QuizLiveTest do
  require Logger
  use BirdSongWeb.LiveCase
  use BirdSong.MockApiCase
  alias BirdSong.TestHelpers
  alias ExUnit.CaptureLog
  alias BirdSong.Bird
  alias BirdSong.Services.XenoCanto

  @moduletag services: [:ebird, :xeno_canto]

  @path "/quiz"

  @ebird_path "/v2/data/obs/US-NC-067/recent"
  @xeno_canto_path "/api/2/recordings"

  @raw_data "test/mock_data/recent_observations.json"
            |> Path.relative_to_cwd()
            |> File.read!()

  @full_mock_expects [
    {"GET", @ebird_path, &__MODULE__.ebird_success_response/1},
    {"GET", @xeno_canto_path, &__MODULE__.xeno_canto_success_response/1}
  ]

  setup %{conn: conn, xeno_canto_cache: cache} do
    {:ok, view, html} = live(conn, @path)
    send(view.pid, {:register_render_listener, self()})
    send(view.pid, {:xeno_canto_cache_pid, cache})
    {:ok, view: view, html: html}
  end

  @tag expect: @full_mock_expects
  test("connected mount", %{view: view, html: html}) do
    CaptureLog.capture_log(fn ->
      assert html =~ "How well do you know your bird songs?"
      assert view |> form("#settings") |> render_submit() =~ "Loading..."
      assert_receive %{bird_count: count} when count > 0

      assert_receive %{current_bird: %{bird: %Bird{}, recording: %XenoCanto.Recording{}}}

      assert render(view) =~ "What bird do you hear?"
    end)
    |> TestHelpers.parse_logs()
    |> Enum.each(&assert &1 =~ "api_calls_remaining")
  end

  describe "start event" do
    @tag expect: &__MODULE__.ebird_success_response/1
    test "fetches recent observations and saves them to state when response is successful", %{
      view: view
    } do
      CaptureLog.capture_log(fn ->
        assert view
               |> form("#settings", quiz: %{})
               |> render_submit()

        assert_receive %{bird_count: count} when count > 0
      end)
    end

    @tag expect: @full_mock_expects
    test "fetches recordings for all birds", %{view: view} do
      CaptureLog.capture_log(fn ->
        assert view
               |> form("#settings", quiz: %{})
               |> render_submit()

        assert await_all_recordings() === :ok
      end)
    end
  end

  @tag :skip
  describe "user can enter a location" do
    @tag use_mock: false
    test "by typing", %{conn: conn} do
      assert {:ok, view, html} = live(conn, @path)
      assert html =~ "Winston Salem, NC"

      assert view
             |> form("#settings", quiz: %{region: "Greensboro, NC"})
             |> render_submit() =~ "Greensboro, NC"
    end

    @tag use_mock: false
    test "by using their browser location" do
    end

    @tag use_mock: false
    test "and be shown an error when the location is not recognized" do
    end
  end

  def ebird_success_response(conn) do
    Plug.Conn.resp(conn, 200, @raw_data)
  end

  def xeno_canto_success_response(%Conn{params: %{"query" => _query}} = conn) do
    Conn.resp(conn, 200, Map.fetch!(@recordings, @red_shouldered_hawk.sci_name))
  end

  def await_all_recordings() do
    receive do
      %{bird_count: count} when count === 0 ->
        await_all_recordings()

      %{bird_count: count, birds: birds_ets, xeno_canto_cache: xc_cache} when count > 0 ->
        if birds_ets |> :ets.tab2list() |> Enum.all?(&has_recordings?(&1, xc_cache)),
          do: :ok,
          else: await_all_recordings()

      _ ->
        await_all_recordings()
    end
  end

  def await_observations() do
    receive do
      %{birds: birds} when Kernel.map_size(birds) === 0 ->
        await_observations()

      %{birds: birds} when Kernel.map_size(birds) > 0 ->
        :ok
    end
  end

  defp has_recordings?({"" <> _, %Bird{} = bird}, xc_cache) do
    case XenoCanto.Cache.get_from_cache(bird, xc_cache) do
      {:ok, %XenoCanto.Response{}} -> true
      :not_found -> false
    end
  end
end
