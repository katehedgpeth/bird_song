defmodule BirdSong.Services.EbirdTest do
  use ExUnit.Case

  alias BirdSong.Services.RequestThrottler.ForbiddenExternalURLError
  alias BirdSong.Services.Supervisor.UnknownOptionKeyError

  alias BirdSong.{
    MockServer,
    Services.Ebird,
    Services.Service,
    Services.RequestThrottler,
    TestHelpers,
    TestSetup
  }

  describe "opts_for_child" do
    test "with default options" do
      assert [
               {
                 RequestThrottler,
                 name: Ebird.RequestThrottler, base_url: "https://api.ebird.org"
               },
               {
                 Ebird.RegionETS,
                 name: Ebird.RegionETS
               },
               {
                 Ebird.Observations,
                 throttler: Ebird.RequestThrottler,
                 name: Ebird.Observations,
                 base_url: "https://api.ebird.org"
               },
               {
                 Ebird.RegionSpeciesCodes,
                 throttler: Ebird.RequestThrottler,
                 name: Ebird.RegionSpeciesCodes,
                 base_url: "https://api.ebird.org"
               },
               {
                 Ebird.Regions,
                 throttler: Ebird.RequestThrottler,
                 name: Ebird.Regions,
                 base_url: "https://api.ebird.org"
               },
               {
                 Ebird.RegionInfo,
                 throttler: Ebird.RequestThrottler,
                 name: Ebird.RegionInfo,
                 base_url: "https://api.ebird.org"
               }
             ] = Ebird.child_specs___test([])
    end

    @tag :tmp_dir
    test "with overriding options", %{tmp_dir: tmp_dir, test: test} do
      base_url = "http://localhost:9000"

      expected_cache_opts = fn name ->
        [
          throttler: Module.concat(test, :RequestThrottler),
          name: Module.concat(test, name),
          base_url: base_url,
          data_folder_path: tmp_dir
        ]
      end

      assert [throttler, region_ets, observations, region_codes, regions, region_info] =
               Ebird.child_specs___test(
                 service_name: test,
                 base_url: base_url,
                 throttle_ms: 5_000,
                 data_folder_path: tmp_dir
               )

      assert throttler === {
               RequestThrottler,
               name: Module.concat(test, :RequestThrottler),
               base_url: base_url,
               throttle_ms: 5_000
             }

      assert region_ets === {
               Ebird.RegionETS,
               name: Module.concat(test, :RegionETS)
             }

      assert observations === {Ebird.Observations, expected_cache_opts.(:Observations)}

      assert region_codes ===
               {Ebird.RegionSpeciesCodes, expected_cache_opts.(:RegionSpeciesCodes)}

      assert regions === {Ebird.Regions, expected_cache_opts.(:Regions)}
      assert region_info === {Ebird.RegionInfo, expected_cache_opts.(:RegionInfo)}
    end

    test "with unknown options" do
      assert_raise UnknownOptionKeyError, fn ->
        Ebird.child_specs___test(throttler: :Throttler)
      end
    end
  end

  describe "names" do
    test "for children", %{test: test} do
      for child <- [:RequestThrottler, :Observations, :RegionInfo, :RegionSpeciesCodes, :Regions] do
        for parent <- [Ebird, test] do
          assert Ebird.child_name(parent, child) === Module.concat(parent, child)
        end
      end
    end
  end

  @tag :tmp_dir
  test "start_link", %{test: test} do
    bypass = Bypass.open()
    Bypass.expect(bypass, &MockServer.success_response/1)

    opts = [
      service_name: test,
      base_url: TestHelpers.mock_url(bypass)
    ]

    start_supervised!({Ebird, opts})

    children =
      test
      |> Ebird.whereis_supervisor!()
      |> Supervisor.which_children()
      |> Enum.map(&elem(&1, 0))

    assert children === [
             Ebird.RegionInfo,
             Ebird.Regions,
             Ebird.RegionSpeciesCodes,
             Ebird.Observations,
             Ebird.RegionETS,
             RequestThrottler
           ]

    throttler = Ebird.child_name(opts, :RequestThrottler)
    throttler_pid = GenServer.whereis(throttler)
    assert is_pid(throttler_pid)
    assert GenServer.call(throttler, :base_url) === TestHelpers.mock_url(bypass)

    assert {:ok, %Ebird.Regions.Region{} = region} =
             Ebird.RegionETS.get(
               "US-NC",
               Ebird.child_name(opts, :RegionETS)
             )

    [observations, regions, _region_info, _region_species_codes] =
      for child <- [
            :Observations,
            :Regions,
            :RegionInfo,
            :RegionSpeciesCodes
          ] do
        service = Ebird.get_instance_child(test, child)
        assert %Service{} = service

        assert service.module |> GenServer.whereis() |> is_pid(),
               "#{inspect(service)} is not started"

        assert service.module === Module.concat(Ebird, child)
        refute is_nil(service.whereis)
        refute GenServer.whereis(service.module) === service.whereis

        assert %{throttler: ^throttler_pid} = GenServer.call(service.whereis, :state)

        assert %{throttler: real_throttler_pid} = GenServer.call(service.module, :state)
        refute real_throttler_pid === throttler_pid

        bypass_url = TestHelpers.mock_url(bypass)

        refute GenServer.call(real_throttler_pid, :base_url) === bypass_url

        assert {:error, %ForbiddenExternalURLError{}} =
                 GenServer.call(real_throttler_pid, :base_url)

        assert GenServer.call(throttler_pid, :base_url) === bypass_url

        service
      end

    assert {:error, %ForbiddenExternalURLError{}} =
             Ebird.Observations.get_recent_observations("US-NC-067", observations.module)

    # cache is warmed on startup
    assert {:ok, [%Ebird.Regions.Region{} | _]} =
             Ebird.Regions.get_subregions(
               region,
               regions.module,
               :subnational2
             )

    for name_or_pid <- [:name, :whereis] do
      assert {:ok, %Ebird.Observations.Response{}} =
               Ebird.Observations.get_recent_observations(
                 "US-NC-067",
                 Map.fetch!(observations, name_or_pid)
               )

      assert {:ok, [%Ebird.Regions.Region{} | _]} =
               Ebird.Regions.get_subregions(
                 region,
                 Map.fetch!(regions, name_or_pid),
                 :subnational2
               )
    end

    # for name_or_pid <- region_info do
    # end

    # for name_or_pid <- region_species_codes do
    #   assert {:ok, %Ebird.RegionSpeciesCodes.Response{}} =
    #            Ebird.RegionSpeciesCodes.get_codes(region, name_or_pid)
    # end
  end

  describe "services/1" do
    @describetag :tmp_dir
    @describetag service: :Ebird

    use TestSetup, [:setup_bypass, :start_service_supervisor!]

    test "returns a struct with all Ebird service instances", %{
      test: test,
      supervisor: supervisor
    } do
      assert %Service{name: instance_name} = supervisor
      services = Ebird.services(instance_name)

      assert %Ebird{} = services

      keys = services |> Map.from_struct() |> Map.keys()

      assert keys === [:Observations, :RegionInfo, :RegionSpeciesCodes, :Regions]

      for key <- keys do
        assert %Service{name: name, module: module, whereis: whereis} = Map.fetch!(services, key)
        refute name === nil
        assert module === Module.concat(Ebird, key)
        assert name === Module.concat(test, key)
        assert is_pid(whereis)
        assert whereis === GenServer.whereis(name)
      end
    end
  end
end
