defmodule BirdSong.Services.Supervisors.EbirdTest do
  use ExUnit.Case

  alias BirdSong.{
    MockServer,
    Services.Ebird,
    Services.Supervisor,
    Services.RequestThrottler,
    TestHelpers
  }

  test "start_link", %{test: test} do
    bypass = Bypass.open()
    Bypass.expect(bypass, &MockServer.success_response/1)

    opts = [
      parent_name: test,
      base_url: TestHelpers.mock_url(bypass)
    ]

    start_supervised!({Supervisor.Ebird, opts})

    children = Supervisor.Ebird.children(test)

    assert Map.keys(children) === [
             Ebird.Observations,
             Ebird.RegionInfo,
             Ebird.RegionSpeciesCodes,
             Ebird.Regions,
             Ebird.Regions.RegionETS,
             RequestThrottler
           ]

    throttler = Supervisor.Ebird.child_name(opts, :Throttler)
    throttler_pid = GenServer.whereis(throttler)
    assert is_pid(throttler_pid)
    assert GenServer.call(throttler, :base_url) === TestHelpers.mock_url(bypass)

    assert {:ok, %Ebird.Regions.Region{} = region} =
             Ebird.Regions.RegionETS.get(
               "US-NC",
               Supervisor.Ebird.child_name(opts, [:Regions, :RegionETS])
             )

    [observations, regions, region_info, region_species_codes] =
      for child_atom <- [
            :Observations,
            :Regions,
            :RegionInfo,
            :RegionSpeciesCodes
          ] do
        child = Module.concat(Ebird, child_atom)
        pid = Supervisor.Ebird.get_child(child, test)
        assert is_pid(pid)
        assert child |> GenServer.whereis() |> is_pid(), "#{child} is not started"
        refute GenServer.whereis(child) === pid
        assert %{throttler: ^throttler_pid} = GenServer.call(pid, :state)
        [pid, Supervisor.Ebird.child_name(opts, child_atom)]
      end

    for name_or_pid <- observations do
      assert {:ok, %Ebird.Observations.Response{}} =
               Ebird.Observations.get_recent_observations("US-NC-067", name_or_pid)
    end

    for name_or_pid <- regions do
      assert {:ok, [%Ebird.Regions.Region{} | _]} =
               Ebird.Regions.get_subregions(region, name_or_pid, :subnational2)
    end

    # for name_or_pid <- region_info do
    #   assert {:ok, %Ebird.RegionInfo{}} = Ebird.RegionInfo.get_info(region, name_or_pid)
    # end

    # for name_or_pid <- region_species_codes do
    #   assert {:ok, %Ebird.RegionSpeciesCodes.Response{}} =
    #            Ebird.RegionSpeciesCodes.get_codes(region, name_or_pid)
    # end
  end
end
