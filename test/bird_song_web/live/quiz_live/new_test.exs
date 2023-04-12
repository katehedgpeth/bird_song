defmodule BirdSongWeb.QuizLive.NewTest do
  use BirdSongWeb.LiveCase
  import BirdSong.TestSetup

  alias Phoenix.LiveViewTest

  alias BirdSong.{
    MockServer,
    Services,
    Services.Ebird,
    Services.Service
  }

  @moduletag :capture_log

  @path "/quiz/new"
  @malformed_code_response_title Enum.join(
                                   ~w(Field regionCode of sppListCmd:
                                 Property regionCode threw exception;
                                 nested exception is java.lang.IllegalArgumentException:
                                 Unable to find matching region type for US-NC-1000),
                                   " "
                                 )
  @malformed_code_response Jason.encode!(%{
                             errors: %{
                               status: "400 BAD_REQUEST",
                               code: "methodInvocation",
                               title: @malformed_code_response_title
                             }
                           })

  setup [
    :seed_from_mock_taxonomy,
    :start_throttler,
    :start_services,
    :start_view,
    :setup_listeners
  ]

  describe "connected mount" do
    @tag expect: &MockServer.success_response/1
    @tag setup_listeners?: false
    test "redirects to /quiz when form is successfully submitted", %{
      view: view,
      html: html
    } do
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

    @tag expect: &__MODULE__.empty_response/1
    test "shows an error if API returns a list of 0 birds for a region", %{
      view: view
    } do
      assert_receive {:render, %{flash: flash}}
      assert flash === %{}

      html =
        view
        |> LiveViewTest.element("#region-btn")
        |> LiveViewTest.render_click(%{"value" => "US-NC-000"})

      assert html =~ "US-NC-000"

      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes}}, 500

      assert_receive {:render, %{flash: %{"error" => error}}}
      assert error =~ "Please choose a different or broader region"
    end

    @tag expect: &__MODULE__.bad_400_response/1
    test "shows an error if API returns 400 (malformed region code)", %{
      view: view
    } do
      assert_receive {:render, %{flash: flash}}
      assert flash === %{}

      html =
        view
        |> LiveViewTest.element("#region-btn")
        |> LiveViewTest.render_click(%{"value" => "US-NC-1000"})

      assert html =~ "US-NC-1000"

      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes}}, 500
      assert_receive {:render, %{flash: %{"error" => error}}}
      assert error =~ "Please try again later."
    end
  end

  def start_view(%{
        conn: conn,
        services: services
      }) do
    {:ok, view, html} = live(conn, @path)
    send(view.pid, {:services, services})
    {:ok, view: view, html: html}
  end

  def setup_listeners(%{setup_listeners?: false}), do: :ok

  def setup_listeners(%{
        view: view,
        services: %Services{
          region_species_codes: %Service{
            whereis: codes_service_pid
          }
        }
      }) do
    send(view.pid, {:register_render_listener, self()})
    Ebird.RegionSpeciesCodes.register_request_listener(codes_service_pid)
  end

  def empty_response(conn) do
    Plug.Conn.resp(conn, 200, "[]")
  end

  def bad_400_response(conn) do
    Plug.Conn.resp(conn, 400, @malformed_code_response)
  end
end
