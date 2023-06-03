defmodule BirdSong.StaticDataTest do
  use BirdSong.DataCase

  alias BirdSong.{
    Bird,
    Family,
    Order,
    Region,
    Repo
  }

  @moduletag seed_regions?: false

  describe "&seed/1" do
    test "seeds both regions and birds" do
      schemas = [
        Bird,
        Family,
        Order,
        Region
      ]

      for schema <- schemas do
        assert Repo.all(schema) === []
      end

      assert BirdSong.StaticData.seed!("test/mock_data") === :ok

      for schema <- schemas do
        assert [_ | _] = Repo.all(schema)
      end
    end
  end
end
