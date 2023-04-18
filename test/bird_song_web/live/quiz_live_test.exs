defmodule BirdSongWeb.QuizLiveTest do
  require Logger
  use BirdSong.MockApiCase, use_data_case: false
  use BirdSongWeb.LiveCase
  alias Phoenix.LiveViewTest
  alias BirdSong.{Bird, Services.XenoCanto}

  @moduletag services: [:ebird, :xeno_canto]
  @moduletag :capture_log

  @path "/quiz/new"

  setup %{conn: conn, services: services} do
    {:ok, view, html} = live(conn, @path)
    send(view.pid, {:register_render_listener, self()})
    send(view.pid, {:services, services})
    {:ok, view: view, html: html}
  end

  @tag expect: &MockServer.success_response/1
  describe "connected mount" do
    setup [:seed_from_mock_taxonomy]

    test("connected mount", %{view: view, html: html}) do
      assert html =~ "How well do you know your bird songs?"
      refute html =~ "US-NC-067"

      html =
        view
        |> LiveViewTest.element("#region-btn")
        |> LiveViewTest.render_click(%{"value" => "US-NC-067"})

      assert html =~ "US-NC-067"

      view
      |> LiveViewTest.element("#species-filter")
      |> LiveViewTest.has_element?()

      assert view
             |> form("#settings")
             |> render_submit() === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
    end
  end

  describe "start event" do
    setup [:seed_from_mock_taxonomy]
    @describetag expect: &MockServer.success_response/1

    @tag :broken
    test "fetches recent observations and saves them to state when response is successful", %{
      view: view
    } do
      assert view
             |> form("#settings", quiz: %{})
             |> render_submit()

      assert_current_gets_assigned()
    end

    @tag :broken
    test "fetches recordings for bird", %{view: view} do
      assert view
             |> form("#settings", quiz: %{})
             |> render_submit()

      assert_current_gets_assigned()
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
