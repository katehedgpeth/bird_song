defmodule BirdSong.Data.CountsTest do
  use BirdSong.DataCase
  import BirdSong.TestSetup

  alias BirdSong.{
    Bird,
    Data.Counts,
    Services,
    Services.DataFile,
    Services.Service
  }

  @moduletag use_mock_routes?: false
  @moduletag :capture_log

  @expected_in_db 300

  setup_all do
    {:ok,
     folder_sizes:
       "data"
       |> File.ls!()
       |> Enum.map(&Path.join("data", &1))
       |> Enum.filter(&(File.lstat!(&1).type === :directory))
       |> Enum.map(&{&1, Counts.get_folder_size(%{name: &1}, 0)})
       |> Map.new()}
  end

  setup [:start_throttler]

  test "&get/1 raises if the database is empty" do
    assert BirdSong.Repo.all(Bird) === []
    assert_raise Counts.NoBirdsError, fn -> Counts.get(%Services{}, %{}) end
  end

  describe "&get/1" do
    @describetag :tmp_dir
    setup [:seed_from_mock_taxonomy, :start_services]

    @tag :tmp_dir
    test "returns a correct count of birds in DB when there is no data", %{services: services} do
      assert Bird |> BirdSong.Repo.all() |> length() === @expected_in_db

      assert %Counts{
               data_folder_bytes: _,
               has_images: 0,
               has_recordings: 0,
               missing_images: @expected_in_db,
               missing_recordings: @expected_in_db,
               total_birds: @expected_in_db
             } = Counts.get(services, %{})
    end

    test "returns correct count of missing recordings", %{
      services: services
    } do
      assert %Services{images: images, recordings: recordings} = services

      refute Service.data_folder_path(recordings) === Service.data_folder_path(images)

      add_fake_files(recordings)

      expected_recordings = @expected_in_db - 3

      assert %Counts{
               has_images: 0,
               has_recordings: 3,
               missing_images: @expected_in_db,
               missing_recordings: ^expected_recordings,
               total_birds: @expected_in_db
             } = Counts.get(services, %{})
    end

    test "returns correct count of missing images", %{services: services} do
      services
      |> Map.fetch!(:images)
      |> add_fake_files()

      expected_images = @expected_in_db - 3

      assert %Counts{
               has_images: 3,
               has_recordings: 0,
               missing_images: ^expected_images,
               missing_recordings: @expected_in_db,
               total_birds: @expected_in_db
             } = Counts.get(services, %{})
    end

    test "returns size of total data folder", %{
      folder_sizes: folder_sizes,
      services: services,
      tmp_dir: tmp_dir
    } do
      assert %{
               "data/images" => images,
               "data/recordings" => recordings,
               "data/regions" => regions,
               "data/region_info" => region_info
             } = folder_sizes

      assert recordings === 89_928_626
      assert images === 10_099_859
      assert regions === 641_644
      assert region_info === 411_569

      services
      |> Map.fetch!(:images)
      |> add_fake_files()

      assert File.ls!(tmp_dir) === ["recordings", "images"]
      assert Path.join(tmp_dir, "recordings") |> File.ls!() === []

      image_files = Path.join(tmp_dir, "images") |> File.ls!()

      assert [_, _, _] = image_files

      for file <- image_files do
        assert String.ends_with?(file, ".json")
      end

      size =
        image_files
        |> Enum.map(&Path.join([tmp_dir, "images", &1]))
        |> Enum.reduce(0, &(File.lstat!(&1).size + &2))

      assert size > 0

      tmp_dir_size = Counts.get_folder_size(%{name: tmp_dir}, 0)

      assert size === tmp_dir_size

      expected_size = tmp_dir_size + regions + region_info

      assert %Counts{
               data_folder_bytes: ^expected_size,
               total_birds: @expected_in_db
             } = Counts.get(services, %{})
    end

    test "filters by region when provided as an argument", %{
      services: services,
      bypass: bypass,
      folder_sizes: folder_sizes
    } do
      assert %{"data/regions" => regions, "data/region_info" => region_info} = folder_sizes

      species_codes =
        "test/mock_data/region_species_codes/US-NC-067.json"
        |> File.read!()
        |> Jason.decode!()
        |> Enum.take(10)
        |> Jason.encode!()

      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 200, species_codes)
      end)

      assert Counts.get(services, %{region: "US-NC-067"}) === %Counts{
               data_folder_bytes: regions + region_info,
               has_images: 0,
               has_recordings: 0,
               missing_images: 10,
               missing_recordings: 10,
               total_birds: 10
             }
    end
  end

  defp add_fake_files(%Service{} = service) do
    Bird
    |> BirdSong.Repo.all()
    |> Enum.take(3)
    |> Enum.each(&add_fake_file(&1, service))
  end

  defp add_fake_file(%Bird{} = bird, %Service{} = service) do
    service
    |> service.module.data_file_instance()
    |> GenServer.call({:data_file_path, %DataFile.Data{request: bird, service: service}})
    |> File.write!(~s({"foo": "bar"}))
  end
end
