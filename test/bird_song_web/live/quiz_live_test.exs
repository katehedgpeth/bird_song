defmodule BirdSongWeb.QuizLiveTest do
  require Logger
  use BirdSongWeb.LiveCase
  use BirdSong.MockApiCase
  alias ExUnit.CaptureLog
  alias BirdSong.Bird
  alias BirdSong.Services.XenoCanto.Recording

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

  @tag stub: [
         {"GET", @ebird_path, &__MODULE__.ebird_success_response/1},
         {"GET", @xeno_canto_path, &__MODULE__.xeno_canto_success_response/1}
       ]
  test("connected mount", %{conn: conn}) do
    CaptureLog.capture_log(fn ->
      assert {:ok, view, html} = live(conn, @path)
      send(view.pid, {:register_render_listener, self()})
      assert html =~ "How well do you know your bird songs?"
      assert view |> form("#settings") |> render_submit() =~ "Loading..."
      # assert Enum.at(birds, 0) |> Tuple.to_list() |> List.first() == "FAIL"
      # IO.inspect(birds)
      assert_receive %{birds: birds} when Kernel.map_size(birds) > 0
      assert_receive %{current_bird: {%Bird{}, %Recording{}}}

      assert render(view) =~ "What bird do you hear?"
    end)
  end

  describe "start event" do
    @tag expect: &__MODULE__.ebird_success_response/1
    test "fetches recent observations and saves them to state when response is successful", %{
      conn: conn
    } do
      CaptureLog.capture_log(fn ->
        assert {:ok, view, _html} = live(conn, @path)

        send(view.pid, {:register_render_listener, self()})

        assert view
               |> form("#settings", quiz: %{})
               |> render_submit()

        assert_receive %{birds: birds} when Kernel.map_size(birds) > 0
      end)
    end

    @tag expect: @full_mock_expects
    test "fetches recordings for all birds", %{conn: conn, bypass: _bypass} do
      CaptureLog.capture_log(fn ->
        assert {:ok, view, _html} = live(conn, @path)
        send(view.pid, {:register_render_listener, self()})

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
    Conn.resp(conn, 200, Map.fetch!(@recordings, @red_shouldered_hawk))
  end

  def await_all_recordings() do
    receive do
      %{birds: birds} when Kernel.map_size(birds) === 0 ->
        await_all_recordings()

      %{birds: birds} ->
        if Enum.all?(birds, &has_recordings?/1),
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

  defp has_recordings?({"" <> _, %Bird{recordings: []}}), do: false
  defp has_recordings?({"" <> _, %Bird{recordings: [_ | _]}}), do: true
end
