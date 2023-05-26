defmodule BirdSong.Services.MacaulayLibraryTest do
  use BirdSong.SupervisedCase

  alias BirdSong.Services.Supervisor.ForbiddenExternalURLError
  alias BirdSong.Services.MacaulayLibrary

  @moduletag service: :MacaulayLibrary

  describe "child_specs" do
    @tag start_services?: false
    test "returns a child spec for all expected children without override", %{} do
      assert [
               request_throttler,
               playwright,
               recordings
             ] = MacaulayLibrary.child_specs___test([])

      assert {MacaulayLibrary.RequestThrottler, throttler_opts} = request_throttler

      assert Keyword.keys(throttler_opts) === [:worker, :base_url]

      assert [
               worker: %Worker{instance_name: MacaulayLibrary.RequestThrottler},
               base_url:
                 {:error,
                  %ForbiddenExternalURLError{
                    opts: forbidden_url_opts
                  }}
             ] = throttler_opts

      assert Keyword.fetch!(forbidden_url_opts, :base_url) ===
               "https://search.macaulaylibrary.org"

      assert {MacaulayLibrary.Playwright,
              [
                worker: %Worker{instance_name: MacaulayLibrary.Playwright},
                base_url: {:error, %ForbiddenExternalURLError{}}
              ]} = playwright

      assert {MacaulayLibrary.Recordings,
              [
                worker: %Worker{instance_name: MacaulayLibrary.Recordings}
              ]} = recordings
    end

    @tag start_services?: false
    test "returns a child spec for all expected children", %{test: test} do
      {:ok, uri} = Bypass.open() |> TestHelpers.mock_url() |> URI.new()

      assert [request_throttler, playwright, recordings] =
               MacaulayLibrary.child_specs___test(
                 service_name: test,
                 base_url: URI.to_string(uri)
               )

      name = Module.concat(test, :RequestThrottler)

      assert {MacaulayLibrary.RequestThrottler,
              worker: %Worker{instance_name: ^name}, base_url: ^uri} = request_throttler

      name = Module.concat(test, :Playwright)

      assert {MacaulayLibrary.Playwright, worker: %Worker{instance_name: ^name}, base_url: ^uri} =
               playwright

      name = Module.concat(test, :Recordings)

      assert {MacaulayLibrary.Recordings, worker: %Worker{instance_name: ^name}} = recordings
    end
  end

  describe "start_link" do
    test "starts ML.Recordings, ML.RequestThrottler, and ML.Playwright", %{
      test: test
    } do
      services =
        MacaulayLibrary
        |> get_service_name(%{test: test})
        |> MacaulayLibrary.services()

      assert %MacaulayLibrary{} = services

      assert services
             |> Map.from_struct()
             |> Map.keys() === [:Recordings, :name]

      assert MacaulayLibrary.base_url(services.name) =~ "http://localhost"

      # assert MacaulayLibrary.Recordings.get()
    end
  end
end
