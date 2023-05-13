defmodule BirdSong.Services.Ebird.RegionInfoTest do
  alias BirdSong.Services.Ebird
  use BirdSong.SupervisedCase

  describe "get_info/2" do
    test "retrieves region info", tags do
      assert %{worker: worker, bypass: bypass} = get_worker_setup(Ebird, :RegionInfo, tags)
      Bypass.down(bypass)

      assert {:ok, %Ebird.RegionInfo{}} =
               Ebird.RegionInfo.get_info(%Ebird.Region{code: "TG"}, worker)
    end
  end
end
