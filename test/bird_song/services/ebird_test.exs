defmodule BirdSong.Services.EbirdTest do
  use BirdSong.SupervisedCase, use_db?: true

  alias BirdSong.MockEbirdServer

  alias BirdSong.{
    Services,
    Services.Ebird,
    Services.Supervisor.ForbiddenExternalURLError,
    Services.Supervisor.UnknownOptionKeyError,
    Services.Worker
  }

  describe "child_specs" do
    @describetag use_bypass?: false
    @describetag start_services?: false
    test "with default options" do
      assert [
               throttler,
               observations,
               region_species_codes,
               regions,
               region_info
             ] = Ebird.child_specs___test([])

      assert {
               Ebird.RequestThrottler,
               worker: %Worker{instance_name: Ebird.RequestThrottler},
               base_url: {:error, %ForbiddenExternalURLError{opts: url_opts}}
             } = throttler

      assert Keyword.fetch!(url_opts, :base_url) == "https://api.ebird.org"

      assert {
               Ebird.Observations,
               worker: %Worker{instance_name: Ebird.Observations}
             } = observations

      assert {
               Ebird.RegionSpeciesCodes,
               worker: %Worker{instance_name: Ebird.RegionSpeciesCodes}
             } = region_species_codes

      assert {
               Ebird.Regions,
               worker: %Worker{instance_name: Ebird.Regions}
             } = regions

      assert {
               Ebird.RegionInfo,
               worker: %Worker{instance_name: Ebird.RegionInfo}
             } = region_info
    end

    @tag :tmp_dir
    test "with overriding options", %{tmp_dir: tmp_dir, test: test} do
      base_url = "http://localhost:9000"

      parent = %Services.Service{name: test, module: Ebird}

      expected_cache_opts = fn name ->
        [
          worker: %Worker{
            atom: name,
            parent: parent,
            instance_name: Module.concat(test, name),
            module: Module.concat(Ebird, name)
          }
        ]
      end

      assert [throttler, observations, region_codes, regions, region_info] =
               Ebird.child_specs___test(
                 service_name: test,
                 base_url: base_url,
                 throttle_ms: 5_000,
                 data_folder_path: tmp_dir
               )

      assert throttler === {
               Ebird.RequestThrottler,
               worker: %Worker{
                 atom: :RequestThrottler,
                 instance_name: Module.concat(test, :RequestThrottler),
                 module: Ebird.RequestThrottler,
                 parent: parent
               },
               base_url: URI.new!(base_url),
               throttle_ms: 5_000
             }

      assert observations === {Ebird.Observations, expected_cache_opts.(:Observations)}

      assert region_codes ===
               {Ebird.RegionSpeciesCodes, expected_cache_opts.(:RegionSpeciesCodes)}

      assert regions === {Ebird.Regions, expected_cache_opts.(:Regions)}
      assert region_info === {Ebird.RegionInfo, expected_cache_opts.(:RegionInfo)}
    end

    test "with external url and allow_external_calls?: true", %{test: test} do
      base_url = "https://google.com"

      specs =
        [
          service_name: test,
          base_url: base_url,
          allow_external_calls?: true
        ]
        |> Ebird.child_specs___test()
        |> Map.new()

      throttler_specs = specs[Ebird.RequestThrottler]

      assert Ebird.RequestThrottler.start_link_option_keys() === [
               :base_url,
               :name,
               :throttle_ms
             ]

      assert [
               worker: %Services.Worker{},
               base_url: %URI{scheme: "https", host: "google.com", port: 443}
             ] = throttler_specs
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
  test "start_link", %{test: test} = tags do
    MockEbirdServer.setup(tags)
    service_name = get_service_name(Ebird, tags)

    assert service_name === Module.concat(test, :Ebird)

    children =
      service_name
      |> Ebird.whereis_supervisor!()
      |> Supervisor.which_children()
      |> Enum.map(&elem(&1, 0))

    assert children === [
             Ebird.RegionInfo,
             Ebird.Regions,
             Ebird.RegionSpeciesCodes,
             Ebird.Observations,
             Ebird.RequestThrottler
           ]

    assert %{worker: mocked_throttler, mock_url: mock_url} =
             get_worker_setup(Ebird, :RequestThrottler, tags)

    assert Ebird.RequestThrottler.base_url(mocked_throttler) === mock_url

    real_throttler = Ebird.get_instance_child(:RequestThrottler)

    assert %Worker{} = real_throttler

    assert {:error, %ForbiddenExternalURLError{}} =
             Ebird.RequestThrottler.base_url(real_throttler)

    [observations | _] =
      for child <- [
            :Observations,
            :Regions,
            :RegionInfo,
            :RegionSpeciesCodes
          ] do
        worker = Ebird.get_instance_child(service_name, child)
        assert %Worker{} = worker

        assert worker.instance_name |> GenServer.whereis() |> is_pid(),
               "#{inspect(worker.instance_name)} is not started"

        assert worker.module === Module.concat(Ebird, child)
        refute GenServer.whereis(worker.module) === GenServer.whereis(worker.instance_name)

        worker
      end

    real_observations = Ebird.get_instance_child(:Observations)

    assert {:error, %ForbiddenExternalURLError{}} =
             Ebird.Observations.get_recent_observations("US-NC-067", real_observations)

    assert {:ok, %Ebird.Observations.Response{}} =
             Ebird.Observations.get_recent_observations(
               "US-NC-067",
               observations
             )
  end

  describe "services/1" do
    @describetag :tmp_dir
    @describetag service: :Ebird

    test "returns a struct with all Ebird service instances", tags do
      assert %Services{ebird: services} = Services.all(tags[:test])
      assert %Ebird{name: instance_name} = services
      assert instance_name === get_service_name(Ebird, tags)

      keys = services |> Map.from_struct() |> Map.keys() |> MapSet.new()

      assert [:Observations, :RegionInfo, :RegionSpeciesCodes, :Regions, :name]
             |> MapSet.new()
             |> MapSet.difference(keys) == MapSet.new([])

      for key <- Enum.reject(keys, &(&1 === :name)) do
        assert %Worker{instance_name: name, module: module} = Map.fetch!(services, key)
        assert module === Module.concat(Ebird, key)
        assert name === Module.concat([tags[:test], :Ebird, key])
      end
    end
  end
end
