defmodule Mix.Tasks.RecordDataTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup

  alias BirdSong.Services.Ebird.RegionSpeciesCodes
  alias BirdSong.Services.RequestThrottler
  alias BirdSong.Services.Ebird.Recordings

  alias BirdSong.{
    Bird,
    Data.Recorder.Config,
    MockEbirdServer,
    MockServer,
    Services,
    Services.Ebird.Recordings.Playwright,
    Services.Flickr,
    Services.RequestThrottlers.MacaulayLibrary,
    Services.Service,
    TestHelpers
  }

  alias Mix.Tasks.BirdSong.RecordData

  @moduletag :tmp_dir
  @moduletag :capture_log

  @region "US-NC-067"

  setup_all do
    raw_codes = File.read!("test/mock_data/region_species_codes/" <> @region <> ".json")
    {:ok, raw_codes: raw_codes, parsed_codes: Jason.decode!(raw_codes)}
  end

  setup [
    :setup_bypass,
    :seed_from_mock_taxonomy,
    :start_playwright,
    :start_services_with_throttlers,
    :setup_route_mocks,
    :listen_to_services,
    :clean_up_tmp_folder_on_exit
  ]

  describe "&run/1" do
    setup [:expect_ebird_routes]

    @tag expect: &MockServer.success_response/1
    test "fetches data from image and recording services", %{services: services} do
      bird = BirdSong.Repo.get_by(Bird, common_name: "Wilson's Warbler")
      assert %Bird{} = bird

      assert %Service{module: Recordings} = Map.fetch!(services, :recordings)
      assert %Service{module: RegionSpeciesCodes} = Map.fetch!(services, :region_species_codes)

      for key <- [:images, :recordings] do
        assert {:error, {:enoent, _}} =
                 Service.read_from_disk(
                   Map.fetch!(services, key),
                   bird
                 )
      end

      assert RecordData.run(["--bird=Wilson's_Warbler"], services) === :ok

      assert_receive {:start_request, %{module: Recordings}}
      assert_receive {:start_request, %{module: Flickr}}
      assert_receive {:end_request, %{module: Recordings}}
      assert_receive {:end_request, %{module: Flickr}}

      assert {:ok, _} = Service.read_from_disk(services.recordings, bird)
      assert {:ok, _} = Service.read_from_disk(services.images, bird)
    end
  end

  @tag use_mock_routes?: false
  describe "&Config.parse/2" do
    test "parses arguments", %{
      bypass: bypass,
      parsed_codes: parsed_codes,
      raw_codes: raw_codes,
      services: services,
      tmp_dir: tmp_dir
    } do
      Bypass.expect(bypass, &Plug.Conn.resp(&1, 200, raw_codes))

      assert %Config{} === %{
               __struct__: Config,
               birds: [],
               clear_db?: false,
               overwrite_files?: false,
               region_species_codes: nil,
               seed_taxonomy?: false,
               services: nil,
               taxonomy_file: nil
             }

      assert Config.parse(["--seed-taxonomy"], services) === %Config{
               seed_taxonomy?: true,
               services: services
             }

      assert Config.parse(["--taxonomy-file=" <> tmp_dir], services) === %Config{
               seed_taxonomy?: true,
               taxonomy_file: tmp_dir,
               services: services
             }

      assert Config.parse(["--overwrite"], services) === %Config{
               overwrite_files?: true,
               services: services
             }

      eastern_bluebird = BirdSong.Repo.get_by(Bird, common_name: "Eastern Bluebird")

      assert Config.parse(["--bird=Eastern_Bluebird"], services) === %Config{
               services: services,
               birds: [eastern_bluebird]
             }

      assert Config.parse(["--region=US-NC-067"], services) === %Config{
               region_species_codes: MapSet.new(parsed_codes),
               services: services
             }

      assert_raise RuntimeError, fn ->
        Config.parse(["--overwrite-files"], services)
      end
    end
  end

  defp start_playwright(%{}) do
    bypass = Bypass.open()

    {:ok, playwright} =
      Playwright.start_link(
        base_url: TestHelpers.mock_url(bypass),
        listeners: [self()],
        throttle_ms: 0
      )

    {:ok, ebird_bypass: bypass, playwright: playwright}
  end

  defp start_services_with_throttlers(%{playwright: playwright} = tags) do
    {:ok,
     Enum.reduce(
       [
         %{service_module: Flickr},
         %{service_module: RegionSpeciesCodes},
         %{
           service_module: Recordings,
           scraper: {Playwright, playwright},
           throttler_module: MacaulayLibrary,
           bypass_tag: :ebird_bypass
         }
       ],
       [
         services: %Services{},
         throttlers: Map.from_struct(%Services{})
       ],
       &start_service_with_throttler(&2, &1, tags)
     )}
  end

  defp start_service_with_throttler(
         [services: %Services{} = services, throttlers: %{} = throttlers],
         %{service_module: service_module} = args,
         %{} = tags
       ) do
    bypass_tag = Map.get(args, :bypass_tag, :bypass)
    scraper = Map.get(args, :scraper)
    throttler_module = Map.get(args, :throttler_module, RequestThrottler)
    bypass = Map.fetch!(tags, bypass_tag)
    service_type = Service.data_type(service_module)

    {:ok, throttler} =
      throttler_module.start_link(
        base_url: TestHelpers.mock_url(bypass),
        throttle_ms: 0,
        scraper: scraper
      )

    service =
      TestHelpers.start_service_supervised(
        service_module,
        tags
        |> Map.put(:throttler, throttler)
        |> Map.put(:bypass, bypass)
      )

    [
      services: Map.replace!(services, service_type, service),
      throttlers: Map.replace!(throttlers, service_type, throttler)
    ]
  end

  defp use_ebird_bypass(%{ebird_bypass: ebird_bypass} = tags) do
    Map.put(tags, :bypass, ebird_bypass)
  end

  defp expect_ebird_routes(tags) do
    tags
    |> use_ebird_bypass()
    |> MockEbirdServer.setup()
  end
end
