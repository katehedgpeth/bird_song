defmodule BirdSong.Services.Ebird.TaxonomyTest do
  use BirdSong.MockApiCase

  alias BirdSong.{
    Order,
    Services,
    Services.DataFile,
    Services.Ebird.Taxonomy,
    Services.Flickr,
    Services.Service,
    Services.XenoCanto
  }

  @moduletag service: [XenoCanto, Flickr]
  @moduletag :capture_log

  setup_all do
    raw_data = Taxonomy.read_data_file()

    mocked_codes =
      @mocked_birds
      |> Enum.map(fn %{species_code: "" <> species_code} -> species_code end)
      |> MapSet.new()

    short_list = Enum.filter(raw_data, &MapSet.member?(mocked_codes, &1["speciesCode"]))

    {:ok, raw_data: raw_data, mocked_codes: mocked_codes, short_list: short_list}
  end

  setup %{test: test} do
    {:ok, data_file} = DataFile.start_link(name: Module.concat(test, :DataFile))
    {:ok, data_file: data_file}
  end

  describe "&seed/1" do
    @tag :capture_log
    @tag expect: &MockServer.success_response/1
    test "seeds the database and fetches images and recordings",
         %{
           services: services,
           short_list: birds
         } do
      assert length(birds) === 3

      assert {:ok, tasks} = Taxonomy.seed(birds, services)

      assert [%Services{} | _] = tasks

      assert length(tasks) === length(birds)

      assert Enum.map(
               tasks,
               &get_responses_summary/1
             ) === [
               {@eastern_bluebird.common_name, recordings: :ok, images: :ok},
               {@carolina_wren.common_name, recordings: :error, images: :ok},
               {@red_shouldered_hawk.common_name, recordings: :error, images: :error}
             ]
    end
  end

  describe "Family parser functions" do
    setup [:listen_to_services, :insert_order]
    @describetag expect: &MockServer.success_response/1

    @tag :only
    test "&parse_and_insert_families/3 writes multiple families to the DB", %{
      raw_data: raw_data,
      order: order,
      services: services
    } do
      list_size = 10

      assert {:ok, tasks} =
               raw_data
               |> Enum.take(list_size)
               |> Taxonomy.parse_and_insert_families(order, services, [])

      assert length(tasks) === list_size

      assert Process.info(self(), :message_queue_len) ===
               {:message_queue_len,
                list_size
                |> Kernel.*([XenoCanto, Flickr] |> length())
                |> Kernel.*([:start_request, :end_request] |> length())}

      raw_data
      |> Enum.take(list_size)
      |> Enum.each(&assert_services_called/1)
    end

    test "&parse_and_insert_family/3 writes a family to the DB and adds birds", %{
      short_list: birds,
      services: services,
      order: order
    } do
      assert length(birds) === 3

      assert {:ok, [%Services{} | _] = tasks} =
               Taxonomy.parse_and_insert_family(
                 [
                   {
                     birds |> List.first() |> Taxonomy.family_name(),
                     birds
                   }
                 ],
                 order,
                 services,
                 []
               )

      assert length(tasks) === length(birds)

      # 3 birds x 2 services x (1 start message + 1 end message) = 12
      assert Process.info(self(), :message_queue_len) === {:message_queue_len, 12}

      Enum.each(birds, &assert_services_called/1)
    end
  end

  describe "taxonomy form" do
    @describetag use_bypass: false
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

  defp listen_to_services(%{services: %Services{images: images, recordings: recordings}}) do
    for %Service{whereis: whereis, name: name} <- [images, recordings] do
      apply(name, :register_request_listener, [whereis])
    end

    :ok
  end

  defp insert_order(%{short_list: [raw | _]}) do
    {:ok, order} =
      raw
      |> Taxonomy.order_name()
      |> Order.insert()

    {:ok, order: order}
  end

  defp raw(%{"familyComName" => name}, :family_common), do: name
  defp raw(%{"comName" => name}, :common_name), do: name
  defp raw(%{"sciName" => name}, :sci_name), do: name

  defp assert_services_called(bird) do
    common_name = raw(bird, :common_name)
    sci_name = raw(bird, :sci_name)

    for module <- [Flickr, XenoCanto] do
      assert_received {:start_request,
                       %{
                         module: ^module,
                         bird: %Bird{common_name: ^common_name, sci_name: ^sci_name}
                       }}

      assert_received {:end_request,
                       %{
                         module: ^module,
                         bird: %Bird{common_name: ^common_name, sci_name: ^sci_name}
                       }}
    end
  end

  defp get_responses_summary(%Services{
         bird: %Bird{common_name: common_name},
         recordings: %Service{response: {recordings_status, _}},
         images: %Service{response: {images_status, _}}
       }) do
    {common_name, recordings: recordings_status, images: images_status}
  end
end
