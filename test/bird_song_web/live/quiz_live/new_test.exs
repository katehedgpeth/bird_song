defmodule BirdSongWeb.QuizLive.NewTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz/new"
  import BirdSong.TestSetup

  alias Phoenix.{
    LiveView.Socket,
    LiveViewTest
  }

  alias BirdSong.{
    MockEbirdServer,
    Services.Ebird,
    Services.RequestThrottler
  }

  @moduletag :capture_log

  setup [
    :seed_from_mock_taxonomy
  ]

  setup tags do
    {:ok,
     Ebird
     |> get_worker_setup(:RegionSpeciesCodes, tags)
     |> Map.put(:region, Map.get(tags, :region, "US-NC-067"))}
  end

  describe "region input" do
    test "shows an error if region is invalid", tags do
      error_message = "is not a known birding region"

      assert %{view: view} = Map.take(tags, [:view])
      assert LiveViewTest.has_element?(view, "#filters")

      input = element(view, "#region-input")

      type_region(view, "US-NC-")

      assert render(input) =~ "US-NC-"
      refute render(view) =~ error_message

      click_set_region(view)

      assert render(view) =~ error_message
    end

    test "shows filters if region is valid", tags do
      MockEbirdServer.setup(tags)

      assert %{view: view} = Map.take(tags, [:view])

      type_region(view, "US-NC-067")
      click_set_region(view)

      assert has_element?(view, "#species-filter")
    end
  end

  describe "connected mount - success scenarios" do
    setup tags do
      MockEbirdServer.setup(tags)

      assert %{region: region, view: view} = Map.take(tags, [:region, :view])

      refute view
             |> element("#region-input")
             |> render() =~ region

      refute LiveViewTest.has_element?(view, "#species-filter")

      type_region(view, region)
      click_set_region(view)

      {:ok, region: region}
    end

    test "shows species filters when user enters a valid region", tags do
      assert %{view: view, region: region} = Map.take(tags, [:view, :region])
      assert render(view) =~ "How well do you know your bird songs?"

      assert view
             |> element("#region-input")
             |> render() =~ region

      assert view
             |> LiveViewTest.element("#species-filter")
             |> LiveViewTest.has_element?()
    end

    test "clicking on a filter button changes the 'selected' status of the category", %{
      view: view
    } do
      assert %Socket{assigns: assigns} = GenServer.call(view.pid, :socket)

      assert %{birds: birds, species_categories: categories} =
               view
               |> get_assigns()
               |> Map.take([:birds, :species_categories])

      assert length(birds) === 300

      assert map_size(categories) === 54

      for {_, value} <- assigns[:species_categories] do
        assert value === false
      end

      button_text = "Mockingbirds and Thrashers"

      view
      |> LiveViewTest.element("button", button_text)
      |> LiveViewTest.render_click()

      assert %{birds: birds, species_categories: %{} = categories} =
               view
               |> get_assigns()
               |> Map.take([:birds, :species_categories])

      assert length(birds) === 300
      assert categories[button_text] === true

      for {name, selected?} <- categories do
        html =
          view
          |> LiveViewTest.element(~s([data-name="#{name}"]))
          |> LiveViewTest.render()

        selected_attribute = ~s(data-selected="data-selected")

        case name do
          ^button_text ->
            assert selected? === true
            assert html =~ selected_attribute

          _ ->
            assert selected? === false
            refute html =~ selected_attribute
        end
      end
    end

    test "redirects to /quiz when form is successfully submitted", %{view: view} do
      assert view
             |> form("#filters")
             |> render_submit() === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
    end

    test "page is redirected and bird list is filtered when a category has been selected", %{
      conn: conn,
      view: view
    } do
      button_text = "New World Warblers"

      view
      |> LiveViewTest.element("button", button_text)
      |> LiveViewTest.render_click()

      redirect =
        view
        |> form("#filters")
        |> render_submit()

      assert redirect === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
      assert {:ok, view, html} = follow_redirect(redirect, conn)
      assert html =~ "What bird do you hear?"
      birds = get_assigns(view)[:birds]
      assert length(birds) === 300
    end

    test "page is redirected and bird list is not filtered when no category is selected", %{
      view: view,
      conn: conn
    } do
      redirect =
        view
        |> form("#filters")
        |> render_submit()

      assert redirect === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
      assert {:ok, view, html} = follow_redirect(redirect, conn)
      assert html =~ "What bird do you hear?"
      birds = get_assigns(view)[:birds]
      assert length(birds) === 300
    end
  end

  describe "error scenarios" do
    @describetag listen_to: [{Ebird, :RegionSpeciesCodes}]

    setup tags do
      assert %{
               bypass: bypass,
               region: region,
               view: view
             } = Map.take(tags, [:bypass, :region, :view])

      case Map.fetch(tags, :expect) do
        {:ok, {status, body}} ->
          Bypass.expect(bypass, &Plug.Conn.resp(&1, status, body))

        :error ->
          :ok
      end

      type_region(view, region)
      click_set_region(view)

      :ok
    end

    @tag expect: {200, "[]"}
    test "shows an error if API returns a list of 0 birds for a region", %{view: view} do
      assert_receive {:end_request, %{module: Ebird.RegionSpeciesCodes, response: response}}, 500

      assert %RequestThrottler.Response{response: {:ok, []}} = response

      assert get_assigns(view)[:flash] === %{
               "error" =>
                 "\n  Sorry, there do not appear to be any known birds in that region.\n  " <>
                   "Please choose a different or broader region.\n  "
             }
    end

    @tag region: "US-NC-1000"
    test "does not call API when region is invalid", %{
      view: view
    } do
      refute_receive {:end_request, %{module: Ebird.RegionSpeciesCodes}}, 500
      assert %{"error" => error} = get_assigns(view)[:flash]
      assert error =~ "US-NC-1000 is not a known birding region"
    end
  end

  defp get_assigns(view) do
    assert %Socket{assigns: assigns} = GenServer.call(view.pid, :socket)

    assigns
  end

  defp type_region(view, region) do
    view
    |> form("#filters", %{quiz: %{"region" => region}})
    |> render_change()
  end

  defp click_set_region(view) do
    view
    |> element("#region-btn")
    |> render_click()
  end
end
