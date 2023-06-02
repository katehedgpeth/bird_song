defmodule BirdSong.StaticDataTest do
  use BirdSong.DataCase
  @moduletag seed_regions?: false

  describe "&seed/1" do
    test "seeds both regions and birds" do
      inserted = BirdSong.StaticData.seed!("test/mock_data")
      assert inserted.insert_all_family === {4, nil}
      assert inserted.insert_all_order === {2, nil}
      assert inserted.birds === {5, nil}
      assert inserted.insert_all_regions_0 === {117, nil}
    end
  end
end
