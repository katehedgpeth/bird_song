defmodule BirdSong.Services.Ebird.TaxonomyMultiTest do
  use BirdSong.DataCase
  alias Ecto.Multi

  alias BirdSong.{}

  alias BirdSong.{
    Bird,
    Family,
    Order,
    Services.Ebird.Taxonomy
  }

  @moduletag :capture_log

  describe "seed" do
    setup tags do
      %{
        records: Taxonomy.read_data_file("test/mock_data/taxonomy.json"),
        ets_tables:
          Enum.map(
            [:Order, :Family, :Bird],
            &(tags[:test]
              |> Module.concat(&1)
              |> :ets.new([:named_table, :public]))
          )
      }
    end

    test "adds orders, families, and birds to database", %{records: records} do
      multi = Taxonomy.seed(records)

      {_, with_family} = Enum.split_with(records, &(&1[Family.uid_raw_key()] === nil))

      [order_uids, family_uids, bird_uids] =
        for module <- [Order, Family, Bird] do
          with_family
          |> MapSet.new(& &1[module.uid_raw_key()])
          |> MapSet.to_list()
        end

      assert length(bird_uids) === 5
      assert length(family_uids) === 4
      assert length(order_uids) === 2

      assert %Multi{} = multi
      assert Multi.to_list(multi) |> length() === 4
      assert {:ok, inserted} = BirdSong.Repo.transaction(multi)

      assert Map.keys(inserted) === [
               :birds,
               :existing,
               :family,
               :insert_all_family,
               :insert_all_order,
               :order
             ]

      inserted_orders = BirdSong.Repo.all(Order)
      inserted_families = BirdSong.Repo.all(Family)
      inserted_birds = BirdSong.Repo.all(Bird)

      assert length(inserted_birds) === 5
      assert length(inserted_families) === 4
      assert length(inserted_orders) === 2
    end

    test "can be called multiple times", %{records: records} do
      assert length(records) === 5

      assert {:ok, inserted} =
               records
               |> Enum.take(3)
               |> Taxonomy.seed()
               |> Repo.transaction()

      assert inserted.birds === {3, nil}

      assert Repo.all(BirdSong.Bird) |> length() === 3

      assert {:ok, inserted_again} =
               records
               |> Taxonomy.seed()
               |> Repo.transaction()

      assert inserted_again.birds === {2, nil}
      assert Repo.all(BirdSong.Bird) |> length() === 5
    end
  end
end
