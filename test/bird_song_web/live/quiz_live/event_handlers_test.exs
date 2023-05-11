defmodule BirdSongWeb.QuizLive.EventHandlersTest do
  use BirdSong.SupervisedCase, async: true
  use BirdSongWeb.LiveCase
  import BirdSong.TestSetup, only: [seed_from_mock_taxonomy: 1]
  alias Ecto.Changeset
  alias Phoenix.LiveView.Socket

  alias BirdSong.{
    Bird,
    MockEbirdServer,
    Quiz,
    Services.Ebird,
    Services.RequestThrottler
  }

  alias BirdSongWeb.QuizLive.{
    Current,
    EventHandlers
  }

  @default_keys MapSet.new([
                  :__changed__,
                  :asset_cdn,
                  :birds,
                  :current,
                  :filters,
                  :flash,
                  :live_action,
                  :max_api_tries,
                  :render_listeners,
                  :services,
                  :session_id,
                  :task_timeout,
                  :visibility
                ])

  setup [:seed_from_mock_taxonomy]

  describe "set_region" do
    @describetag listen_to: [{Ebird, :RegionSpeciesCodes}]
    setup tags do
      assert %{conn: conn, test: test} = Map.take(tags, [:conn, :test])

      assert {:ok, view, _html} = live(conn, "/quiz/new?service_instance_name=#{test}")

      {:ok,
       Ebird
       |> get_worker_setup(:RegionSpeciesCodes, tags)
       |> Map.merge(%{
         view: view,
         socket: GenServer.call(view.pid, :socket)
       })}
    end

    @tag region: "US-NC-067"
    test "sets region and gets region species codes if region is valid", tags do
      assert %{
               region: code,
               socket: socket
             } = Map.take(tags, [:socket, :region])

      MockEbirdServer.setup(tags)

      assert socket.assigns |> Map.keys() |> MapSet.new() === @default_keys

      assert socket.assigns[:birds] === []
      assert socket.assigns[:current] === %Current{}
      assert %Changeset{valid?: true, data: %Quiz{region: nil}} = socket.assigns[:filters]
      assert socket.assigns[:flash] === %{}

      assert {:noreply, %Socket{assigns: assigns}} =
               EventHandlers.handle_event(
                 "set_region",
                 %{"quiz" => %{"region" => code}},
                 socket
               )

      assert_receive {:start_request,
                      %{
                        module: Ebird.RegionSpeciesCodes,
                        region: ^code
                      }},
                     100

      assert_receive {:end_request,
                      %{
                        module: Ebird.RegionSpeciesCodes,
                        response: response
                      }}

      assert %RequestThrottler.Response{response: {:ok, ["" <> _ | _]}} = response

      assert get_new_assigns(assigns) === [:birds_by_category]

      assert assigns[:flash] === %{}

      assert %Quiz{region: ^code} = assigns[:filters]
      assert [%Bird{} | _] = assigns[:birds]
      assert %{} = assigns[:birds_by_category]
      assert ["Mockingbirds and Thrashers" | _] = Map.keys(assigns[:birds_by_category])

      assert [%{bird: %Bird{}, selected?: false} | _] =
               assigns[:birds_by_category]["Mockingbirds and Thrashers"]
    end

    @tag region: "US-000"
    test "does not assign region or fetch species codes if region is not valid", tags do
      assert %{
               socket: socket,
               region: code
             } = Map.take(tags, [:socket, :region])

      assert %Changeset{errors: []} = socket.assigns[:filters]

      assert {:noreply, %Socket{assigns: assigns}} =
               EventHandlers.handle_event(
                 "set_region",
                 %{"quiz" => %{"region" => code}},
                 socket
               )

      assert get_new_assigns(assigns) === []

      assert %Changeset{errors: [region: error]} = assigns[:filters]

      assert error === {"unknown: #{code}", []}

      assert assigns[:flash] === %{"error" => "US-000 is not a known birding region"}

      refute_receive {:start_request,
                      %{
                        module: Ebird.RegionSpeciesCodes,
                        region: ^code
                      }},
                     300
    end
  end

  defp get_new_assigns(%{} = assigns) do
    assigns
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.difference(@default_keys)
    |> MapSet.to_list()
  end
end
