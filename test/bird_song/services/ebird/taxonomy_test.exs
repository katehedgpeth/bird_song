defmodule BirdSong.Services.Ebird.TaxonomyTest do
  use BirdSong.MockApiCase

  alias BirdSong.{
    Order,
    Services.Ebird.Taxonomy,
    Services.Flickr,
    Services.XenoCanto
  }

  @moduletag service: [XenoCanto, Flickr]
  @moduletag use_mock_routes?: false
  @moduletag :capture_log
  @moduletag seed_data?: false

  setup_all do
    raw_data = Taxonomy.read_data_file()

    mocked_codes =
      @mocked_birds
      |> Enum.map(fn %{species_code: "" <> species_code} -> species_code end)
      |> MapSet.new()

    short_list = Enum.filter(raw_data, &MapSet.member?(mocked_codes, &1["speciesCode"]))

    {:ok, raw_data: raw_data, mocked_codes: mocked_codes, short_list: short_list}
  end

  describe "&seed/1" do
    @tag :capture_log
    test "seeds the database and fetches images and recordings",
         %{
           short_list: raw_birds
         } do
      assert length(raw_birds) === 3

      assert {:ok, inserted_birds} = Taxonomy.seed(raw_birds)

      assert [%Bird{} | _] = inserted_birds

      assert length(raw_birds) === length(inserted_birds)
    end
  end

  describe "Family parser functions" do
    setup [:insert_order]
    @describetag :tmp_dir

    test "&parse_and_insert_families/3 writes multiple families to the DB", %{
      raw_data: raw_data,
      order: order
    } do
      list_size = 10

      assert {:ok, inserted_birds} =
               raw_data
               |> Enum.take(list_size)
               |> Taxonomy.parse_and_insert_families(order, [])

      assert length(inserted_birds) === list_size

      assert Process.info(self(), :message_queue_len) === {:message_queue_len, 0}
    end

    test "&parse_and_insert_family/3 writes a family to the DB and adds birds", %{
      short_list: raw_birds,
      order: order
    } do
      assert length(raw_birds) === 3

      assert {:ok, [%Bird{} | _] = inserted_birds} =
               Taxonomy.parse_and_insert_family(
                 [
                   {
                     raw_birds |> List.first() |> Taxonomy.family_name(),
                     raw_birds
                   }
                 ],
                 order,
                 []
               )

      assert length(inserted_birds) === length(raw_birds)

      assert Process.info(self(), :message_queue_len) === {:message_queue_len, 0}
    end
  end

  describe "taxonomy form" do
    @describetag use_bypass?: false
    test "species codes are unique", %{raw_data: raw_data} do
      assert length(raw_data) === 16_860
      by_species_code = raw_data |> Enum.map(&{&1["speciesCode"], &1})
      assert length(raw_data) === length(by_species_code)
    end

    test "not all species have orders and families", %{raw_data: raw_data} do
      assert {no_order, has_order} = Enum.split_with(raw_data, &(&1["order"] === nil))

      assert length(no_order) === 2
      assert length(has_order) === 16_858

      assert {no_family, has_family} = Enum.split_with(raw_data, &(&1["familyComName"] === nil))
      assert length(no_family) === 13
      assert length(has_family) === 16_847

      assert [
               %{
                 "order" => "Charadriiformes",
                 "category" => "spuh",
                 "comName" => "shorebird sp."
               },
               %{
                 "order" => "Procellariiformes",
                 "category" => "spuh",
                 "comName" => "storm-petrel sp. (dark-rumped)"
               },
               %{
                 "order" => "Procellariiformes",
                 "category" => "spuh",
                 "comName" => "storm-petrel sp. (white-rumped)"
               },
               %{
                 "order" => "Procellariiformes",
                 "category" => "spuh",
                 "comName" => "storm-petrel sp."
               },
               %{"category" => "spuh", "comName" => "diurnal raptor sp."},
               %{"order" => "Psittaciformes", "category" => "spuh", "comName" => "parakeet sp."},
               %{"order" => "Psittaciformes", "category" => "spuh", "comName" => "parrot sp."},
               %{
                 "order" => "Passeriformes",
                 "category" => "hybrid",
                 "comName" => "Yellow-breasted Chat x new world oriole sp. (hybrid)"
               },
               %{
                 "order" => "Passeriformes",
                 "category" => "slash",
                 "comName" => "Chipping Sparrow/Worm-eating Warbler"
               },
               %{
                 "order" => "Passeriformes",
                 "category" => "slash",
                 "comName" => "Dark-eyed Junco/Pine Warbler"
               },
               %{
                 "order" => "Passeriformes",
                 "category" => "spuh",
                 "comName" => "sparrow/warbler sp. (trilling song)"
               },
               %{"order" => "Passeriformes", "category" => "spuh", "comName" => "passerine sp."},
               %{"category" => "spuh", "comName" => "bird sp."}
             ] = Enum.map(no_family, &Map.take(&1, ["category", "comName", "order"]))
    end

    test "counts", %{raw_data: raw_data} do
      assert [
               {"domestic", domestic},
               {"form", form},
               {"hybrid", hybrid},
               {"intergrade", intergrade},
               {"issf", issf},
               {"slash", slash},
               {"species", species},
               {"spuh", spuh}
             ] = raw_data |> Enum.group_by(& &1["category"]) |> Map.to_list()

      assert domestic |> length() === 15
      assert form |> length() === 115
      assert hybrid |> length() === 603
      assert intergrade |> length() === 35
      assert issf |> length() === 3_665
      assert slash |> length() === 840
      assert species |> length() === 10_906
      assert spuh |> length() === 681
    end
  end

  defp insert_order(%{short_list: [raw | _]}) do
    {:ok, order} =
      raw
      |> Taxonomy.order_name()
      |> Order.insert()

    {:ok, order: order}
  end
end
