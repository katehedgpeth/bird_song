defmodule BirdSongWeb.Components.FiltersTest do
  use BirdSongWeb.ConnCase
  use BirdSong.SupervisedCase
  use BirdSong.MockDataAttributes
  import BirdSong.TestSetup

  import Phoenix.LiveViewTest

  alias BirdSong.Family

  alias BirdSong.{
    Accounts,
    Accounts.User,
    Bird,
    MockEbirdServer,
    Services.Ebird,
    Services.RequestThrottler
  }

  alias BirdSongWeb.Components.Filters

  @endpoint BirdSongWeb.Endpoint

  @by_family_filter_selector ~s([phx-value-element="by_family"])

  setup [
    :seed_from_mock_taxonomy,
    :register_and_log_in_user
  ]

  setup %{conn: %Plug.Conn{} = conn, test: test} do
    conn =
      conn
      |> assign_user_token()
      |> BirdSong.PubSub.subscribe()

    assert {:ok, bird} = Bird.get_by_sci_name(@eastern_bluebird.sci_name)

    assert {:ok, view, _html} =
             live_isolated(conn, Filters,
               session: %{
                 "services" => Atom.to_string(test),
                 "user_token" => conn.assigns.user.token
               }
             )

    {:ok, bird: bird, conn: conn, view: view}
  end

  describe "region input" do
    test "has user token and id assigned", %{conn: conn, user: %User{id: user_id}, view: view} do
      assert %User{} = Accounts.get_user!(user_id)
      assigns = get_assigns(view)
      assert assigns.user.id === user_id
      assert assigns.user.token === conn.assigns.user.token
      assert %User{id: ^user_id} = Accounts.get_user_by_session_token(assigns.user.token)
    end

    test "does not show options if entry is less than 3 letters", %{view: view} do
      type_region(view, "fo")

      refute has_element?(view, suggestion_selector("US-NC-067"))
    end

    test "shows region dropdown after user types 3 letters", %{view: view} do
      type_region(view, "For")

      assert %BirdSong.Region{} = BirdSong.Region.from_code!("US-NC-067")

      assert has_element?(view, suggestion_selector("US-NC-067"))

      type_region(view, "forsy")
      assert has_element?(view, suggestion_selector("US-NC-067"))
    end

    @tag listen_to: [{Ebird, :RegionSpeciesCodes}]
    test "shows filter buttons after user selects a region", %{view: view, bird: bird} = tags do
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
      assert has_element?(view, "h3", "Select specific birds or families")
      assert has_element?(view, family_group_selector(bird)) === false
      assert has_element?(view, bird_button_selector(bird)) === false
    end

    test "clicking filters sets birds to selected", %{view: view, bird: bird} = tags do
      MockEbirdServer.setup(tags)

      type_region(view, "for")
      click_region_suggestion(view, "US-NC-067")

      assert has_element?(view, "h3", "Select specific birds or families")
      refute has_element?(view, family_group_selector(bird))
      refute has_element?(view, bird_button_selector(bird))

      view
      |> element(@by_family_filter_selector)
      |> render_click()

      assert has_element?(view, family_group_selector(bird))
      refute has_element?(view, bird_button_selector(bird))

      view
      |> element(family_group_selector(bird))
      |> render_click()

      assert has_element?(view, bird_button_selector(bird))

      html =
        view
        |> element(bird_button_selector(bird))
        |> render_click()

      assert html
             |> Floki.find(bird_button_selector(bird))
             |> Floki.attribute("aria-checked") === ["aria-checked"]

      assert [swainsons_thrush] =
               Bird.get_many_by_common_name(["Swainson's Thrush"])
               |> BirdSong.Repo.preload(:family)

      assert Bird.family_name(swainsons_thrush) === Bird.family_name(bird)

      assert html
             |> Floki.find(bird_button_selector(swainsons_thrush))
             |> Floki.attribute("aria-checked") === []
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
                 "\n  There do not appear to be any known birds in that region.\n  " <>
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

  defp family_group_selector(%Bird{family: %Family{common_name: name}}) do
    ~s([phx-value-family="#{name}"][phx-value-element="families"])
  end

  defp bird_button_selector(%Bird{common_name: name}) do
    ~s([phx-value-bird="#{name}"])
  end

  defp assign_user_token(conn) do
    %{"user_token" => token} = Plug.Conn.get_session(conn)
    Plug.Conn.assign(conn, :user, %{token: token})
  end
end
