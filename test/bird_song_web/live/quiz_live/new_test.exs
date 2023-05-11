defmodule BirdSongWeb.QuizLive.NewTest do
  use BirdSongWeb.SupervisedLiveCase, path: "/quiz/new", async: true
  import BirdSong.TestSetup

  alias Phoenix.{
    LiveView.Socket,
    LiveViewTest
  }

  alias BirdSong.{
    Bird,
    MockEbirdServer,
    Quiz,
    Services.Ebird,
    Services.RequestThrottler
  }

  @filters_id "#filters"

  @region_filter_id "#filter-region"
  @region_form_id @region_filter_id <> "-form"

  @species_filter_id "#filter-by-species"

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
      assert LiveViewTest.has_element?(view, @filters_id)

      refute render(view) =~ error_message

      set_region(view, "US-NC-")

      assert render(view) =~ error_message
    end

    test "shows filters if region is valid", tags do
      MockEbirdServer.setup(tags)

      assert %{view: view} = Map.take(tags, [:view])

      set_region(view, "US-NC-067")

      assert has_element?(view, @species_filter_id)
    end
  end

  describe "connected mount - success scenarios" do
    setup tags do
      MockEbirdServer.setup(tags)

      assert %{region: region, view: view} = Map.take(tags, [:region, :view])

      refute view
             |> element(@region_filter_id)
             |> render() =~ region

      refute LiveViewTest.has_element?(view, @species_filter_id)

      set_region(view, region)

      {:ok, region: region}
    end

    test "clicking the 'select all' checkbox  selects all birds in a category", %{view: view} do
      assert %{birds: birds, birds_by_category: birds_by_category} =
               view
               |> get_assigns()
               |> Map.take([:birds, :birds_by_category])

      assert length(birds) === 300

      assert map_size(birds_by_category) === 54

      for {category, birds} <- birds_by_category do
        for bird <- birds do
          assert bird[:selected?] === false, "category: #{category}"
        end
      end

      category = "Mockingbirds and Thrashers"

      click_category_checkbox(view, category)

      assert %{birds: birds, birds_by_category: %{} = birds_by_category} =
               view
               |> get_assigns()
               |> Map.take([:birds, :birds_by_category])

      assert length(birds) === 300

      for {name, birds} <- birds_by_category do
        should_be_selected? =
          case name do
            ^category -> true
            _ -> false
          end

        for bird <- birds do
          assert bird[:selected?] === should_be_selected?, "category: #{name}"

          assert has_element?(
                   view,
                   ~s(button[aria-checked="aria-checked"]),
                   bird[:bird].common_name
                 ) === should_be_selected?
        end
      end

      assert view
             |> element(~s(label[for="species-filter-#{category}"]), "Deselect all")
             |> render() =~ ~s(checked="checked")
    end

    test "redirects to /quiz when form is successfully submitted", %{view: view} do
      assert click_start_quiz(view) === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
    end

    test "page is redirected and bird list is filtered when a category has been selected", %{
      conn: conn,
      view: view
    } do
      category = "New World Warblers"

      click_category_checkbox(view, category)

      assert {:ok, view, html} =
               view
               |> click_start_quiz()
               |> follow_redirect(conn)

      assert html =~ "What bird do you hear?"
      assigns = get_assigns(view)
      assert %Quiz{birds: birds} = assigns[:quiz]

      assert length(birds) < length(assigns[:birds])
      assert length(birds) === length(assigns[:birds_by_category][category])
    end

    test "page is redirected and bird list is filtered when a category has been incompletely selected",
         %{
           conn: conn,
           view: view
         } do
      view
      |> element(".btn-outline button", "Cerulean Warbler")
      |> render_click()

      warblers = get_assigns(view)[:birds_by_category]["New World Warblers"]

      assert %{selected?: true} =
               Enum.find(warblers, &(&1[:bird].common_name === "Cerulean Warbler"))

      assert {:ok, view, _html} =
               view
               |> click_start_quiz()
               |> follow_redirect(conn)

      assert %Quiz{birds: [%Bird{common_name: "Cerulean Warbler"}]} = get_assigns(view)[:quiz]
    end

    test "page is redirected and bird list is not filtered when no category is selected", %{
      view: view,
      conn: conn
    } do
      redirect = click_start_quiz(view)

      assert redirect === {:error, {:live_redirect, %{kind: :push, to: "/quiz"}}}
      assert {:ok, view, html} = follow_redirect(redirect, conn)
      assert html =~ "What bird do you hear?"
      %Quiz{birds: birds} = get_assigns(view)[:quiz]
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

      set_region(view, region)

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

  defp click_start_quiz(view) do
    view
    |> element("button", "Let's go!")
    |> render_click()
  end

  defguard is_state(state) when state in [:open, :closed]

  defp click_category_checkbox(view, category) do
    view
    |> LiveViewTest.element(~s(label[for="species-filter-#{category}"] input))
    |> LiveViewTest.render_click()
  end

  defp get_assigns(view) do
    assert %Socket{assigns: assigns} = GenServer.call(view.pid, :socket)

    assigns
  end

  defp set_region(view, region) do
    view
    |> form(@region_form_id, %{quiz: %{"region" => region}})
    |> render_submit()
  end
end
