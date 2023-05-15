defmodule BirdSongWeb.Components.FiltersTest do
  use BirdSong.SupervisedCase, use_db?: true
  use BirdSong.MockDataAttributes
  import BirdSong.TestSetup

  import Phoenix.LiveViewTest

  alias BirdSong.{
    MockEbirdServer,
    Services.Ebird,
    Services.RequestThrottler
  }

  alias BirdSongWeb.Components.Filters

  @endpoint BirdSongWeb.Endpoint

  setup %{test: test} do
    session_id = Ecto.UUID.generate()
    conn = Phoenix.ConnTest.build_conn()
    Phoenix.PubSub.subscribe(BirdSong.PubSub, "session:" <> session_id)

    assert {:ok, view, _html} =
             live_isolated(conn, Filters,
               session: %{
                 "services" => Atom.to_string(test),
                 "_csrf_token" => session_id
               }
             )

    {:ok, view: view}
  end

  describe "region input" do
    setup [:seed_from_mock_taxonomy]

    test "does not show options if entry is less than 3 letters", %{view: view} do
      type_region(view, "fo")

      refute has_element?(view, suggestion_selector("US-NC-067"))
    end

    test "shows region dropdown after user types 3 letters", %{view: view} do
      type_region(view, "For")

      assert has_element?(view, suggestion_selector("US-NC-067"))

      type_region(view, "forsy")
      assert has_element?(view, suggestion_selector("US-NC-067"))
    end

    @tag listen_to: [{Ebird, :RegionSpeciesCodes}]
    test "shows filter buttons after user selects a region", %{view: view} = tags do
      MockEbirdServer.setup(tags)

      assert %Services{} =
               services =
               GenServer.call(view.pid, :assigns)
               |> Map.fetch!(:services)

      assert Atom.to_string(services.ebird.name) =~ Atom.to_string(tags[:test])

      type_region(view, "For")
      click_region_suggestion(view, "US-NC-067")

      assert_receive {:region_selected, %BirdSong.Region{code: "US-NC-067"}}
      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes}}, 1_000
      assert has_element?(view, "#filter-by-family")
    end

    test "clicking filters sets birds to selected", %{view: view} = tags do
      MockEbirdServer.setup(tags)

      type_region(view, "for")
      click_region_suggestion(view, "US-NC-067")

      view
      |> element(~s([phx-value-element="by_family"]))
      |> render_click()

      view
      |> element(~s([phx-value-bird="Eastern Bluebird"]))
      |> render_click()

      assert has_element?(view, "#filter-by-family")
    end
  end

  describe "error scenarios" do
    @describetag listen_to: [{Ebird, :RegionSpeciesCodes}]

    setup tags do
      assert %{view: view} = Map.take(tags, [:view])
      region_name = Map.get(tags, :region, "Forsyth")

      assert %{bypass: bypass} = get_worker_setup(Ebird, :RegionSpeciesCodes, tags)

      case Map.fetch(tags, :expect) do
        {:ok, {status, body}} ->
          Bypass.expect(bypass, &Plug.Conn.resp(&1, status, body))

        :error ->
          :ok
      end

      type_region(view, String.downcase(region_name))

      {:ok, region_name: region_name}
    end

    @tag expect: {200, "[]"}
    test "shows an error if API returns a list of 0 birds for a region", %{view: view} do
      assigns = get_assigns(view)
      assert Map.fetch(assigns, :by_family) === {:ok, nil}
      click_region_suggestion(view, "US-NC-067")
      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes, response: response}}, 500

      assert %RequestThrottler.Response{response: {:ok, []}} = response

      assigns = get_assigns(view)
      assert assigns[:by_family] === nil

      assert assigns[:flash] === %{
               "error" =>
                 "\n  Sorry, there do not appear to be any known birds in that region.\n  " <>
                   "Please choose a different or broader region.\n  "
             }
    end

    @tag expect: {500, ~s({"error": "unknown"})}
    test "shows an error if API returns a bad response", %{view: view} do
      click_region_suggestion(view, "US-NC-067")
      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes, response: response}}, 500

      assert %RequestThrottler.Response{response: {:error, _}} = response

      assert get_assigns(view)[:flash] === %{
               "error" =>
                 "\n  We're sorry, but our service is not available at the moment. Please try again later.\n  "
             }
    end
  end

  defp type_region(view, region) do
    view
    |> element("#region")
    |> render_change(%{region: region})
  end

  defp click_region_suggestion(view, region_code) do
    view
    |> element(suggestion_selector(region_code))
    |> render_click()
  end

  defp suggestion_selector(region_code) do
    ~s([phx-value-region="#{region_code}"])
  end

  defp get_assigns(view) do
    GenServer.call(view.pid, :socket).assigns
  end
end
