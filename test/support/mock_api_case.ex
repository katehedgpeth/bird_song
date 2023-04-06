defmodule BirdSong.MockApiCase do
  @moduledoc """
  Handles boilerplate of setting up mocks for external APIs using Bypass.

  Expects all services to have a :base_url config under the :bird_song config.

  Use one of these tags to skip bypass setup:
    * `@tag use_bypass?: false` will skip all bypass setup
    * `@tag use_mock_routes?: false` will initialize bypass but skip setting up expects

  To use the mock setup process, the `:service` tag is always required. This specifies which services
  should have their `:base_url` config updated.
    * `@tag service: [ServiceName, OtherServiceName]`

  Also, one or more of the following tags is required to use the mock setup process:
    * `@tag expect_once: &Module.function/1`
    * `@tag expect_once: [{"" <> method, "" <> path, &Module.function/1}]`
    * `@tag expect: &Module.function/1`
    * `@tag expect: [{"" <> method, "" <> path, &Module.function/1}]`
    * `@tag stub: {"" <> method, "" <> path, &Module.function/1}`
    * `@tag stub: [{"" <> method, "" <> path, &Module.function/1}]`

  Other optional tags:
    * `@tag bird: %Bird{}` - use this to specify which bird the services should return data for.
    * `@tag recordings_service: ModuleName`
    * `@tag images_service: ModuleName`
  """
  use ExUnit.CaseTemplate

  using opts do
    quote location: :keep, bind_quoted: [opts: opts] do
      import BirdSong.TestSetup

      @moduletag seed_services?: Keyword.get(opts, :seed_services?, false)

      if Keyword.get(opts, :use_data_case, true) do
        use BirdSong.DataCase
        setup [:seed_from_mock_taxonomy]
      end

      setup [:start_services]
      setup [:setup_route_mocks]
      setup [:listen_to_services]
      setup [:clean_up_tmp_folder_on_exit]

      require Logger
      use BirdSong.MockDataAttributes

      alias BirdSong.{
        Bird,
        MockServer,
        TestHelpers,
        Services.Ebird
      }

      # @moduletag seed_services?: false
    end
  end
end
