defmodule BirdSong.Services.Ebird.RegionSpeciesCodesTest do
  use BirdSong.SupervisedCase, async: true

  alias BirdSong.{
    MockEbirdServer,
    Services.Ebird,
    Services.Ebird.Region,
    Services.Ebird.RegionSpeciesCodes
  }

  setup tags do
    MockEbirdServer.setup(tags)

    {:ok,
     [
       region: Region.from_code!("US-NC-067"),
       worker: get_worker(Ebird, :RegionSpeciesCodes, tags)
     ]}
  end

  describe "get_codes/2" do
    test "returns %RegionSpeciesCodes.Response{} with a list of codes as strings", tags do
      assert %{region: region, worker: worker} = Map.take(tags, [:region, :worker])
      assert {:ok, response} = RegionSpeciesCodes.get_codes(region, worker)
      assert %RegionSpeciesCodes.Response{} = response
      assert response.region === "US-NC-067"
      assert ["" <> _ | _] = response.codes
    end
  end
end
