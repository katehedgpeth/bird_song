defmodule BirdSongWeb.QuizLiveTest do
  require Logger
  use BirdSong.MockApiCase, use_data_case: false
  use BirdSongWeb.LiveCase
  alias ExUnit.CaptureLog
  alias Phoenix.LiveView.Socket
  alias BirdSongWeb.{QuizLive, QuizLive.EtsTables, QuizLive.Current}
  alias BirdSong.{Bird, Services, Services.XenoCanto, Quiz}

  @moduletag services: [:ebird, :xeno_canto]
  @moduletag :capture_log

  @path "/quiz"

  setup %{conn: conn, services: services} do
    {:ok, view, html} = live(conn, @path)
    send(view.pid, {:register_render_listener, self()})
    send(view.pid, {:services, services})
    {:ok, view: view, html: html}
  end

  @tag use_mock: false
  test "default assigns" do
    %Socket{}
    |> QuizLive.assign_defaults()
    |> TestHelpers.assert_expected_keys([
      :__changed__,
      :birds,
      :current,
      :ets_tables,
      :max_api_tries,
      :quiz,
      :render_listeners,
      :services,
      :show_answer?,
      :show_image?,
      :show_recording_details?,
      :task_timeout,
      :text_input_class
    ])
    |> TestHelpers.assert_assigned(:birds, [])
    |> TestHelpers.assert_assigned(
      :services,
      %Services{}
    )
    |> TestHelpers.assert_assigned(:current, %Current{})
    |> TestHelpers.assert_assigned(
      :ets_tables,
      fn ets_tables ->
        assert %EtsTables{tasks: tasks} = ets_tables
        assert is_reference(tasks), "expected tasks to be a ref but got " <> inspect(tasks)
      end
    )
    |> TestHelpers.assert_assigned(:quiz, Quiz.changeset(%Quiz{}, %{}))
    |> TestHelpers.assert_assigned(:render_listeners, [])
    |> TestHelpers.assert_assigned(:show_answer?, false)
    |> TestHelpers.assert_assigned(:show_image?, false)
    |> TestHelpers.assert_assigned(:show_recording_details?, false)
    |> TestHelpers.assert_assigned(
      :text_input_class,
      &(&1
        |> is_list()
        |> assert("expected :test_input_class to be a list, but got #{&1}"))
    )
  end

  @tag expect: &MockServer.success_response/1
  describe "connected mount" do
    setup [:seed_from_mock_taxonomy]

    test("connected mount", %{view: view, html: html}) do
      CaptureLog.capture_log(fn ->
        assert html =~ "How well do you know your bird songs?"
        assert view |> form("#settings") |> render_submit() =~ "Loading..."
        assert_receive {:render, %{birds: [%Bird{} | _]}}, 1_000

        assert render(view) =~ "What bird do you hear?"
      end)
    end
  end

  describe "start event" do
    setup [:seed_from_mock_taxonomy]
    @describetag expect: &MockServer.success_response/1

    test "fetches recent observations and saves them to state when response is successful", %{
      view: view
    } do
      CaptureLog.capture_log(fn ->
        assert view
               |> form("#settings", quiz: %{})
               |> render_submit()

        assert_current_gets_assigned()
      end)
    end

    test "fetches recordings for bird", %{view: view} do
      CaptureLog.capture_log(fn ->
        assert view
               |> form("#settings", quiz: %{})
               |> render_submit()

        assert_current_gets_assigned()
      end)
    end
  end

  describe "user can enter a location" do
    @describetag :skip

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

  def assert_current_gets_assigned() do
    assert_receive {:render,
                    %{
                      current: %{
                        bird: %Bird{},
                        recording: %XenoCanto.Recording{}
                      }
                    }},
                   5_000
  end
end
