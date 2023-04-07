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

      assert Counts.get(services, %{}) === %Counts{
               data_folder_bytes: 128,
               has_images: 0,
               has_recordings: 0,
               missing_images: @expected_in_db,
               missing_recordings: @expected_in_db,
               total_birds: @expected_in_db
             }
    end

    test "returns correct count of missing recordings", %{
      services: services
    } do
      assert %Services{images: images, recordings: recordings} = services

      refute Service.data_folder_path(recordings) === Service.data_folder_path(images)

      add_fake_files(recordings)

      assert Counts.get(services, %{}) === %Counts{
               data_folder_bytes: 224,
               has_images: 0,
               has_recordings: 3,
               missing_images: @expected_in_db,
               missing_recordings: @expected_in_db - 3,
               total_birds: @expected_in_db
             }
    end

    test "returns correct count of missing images", %{services: services} do
      services
      |> Map.fetch!(:images)
      |> add_fake_files()

      assert Counts.get(services, %{}) === %Counts{
               data_folder_bytes: 224,
               has_images: 3,
               has_recordings: 0,
               missing_images: @expected_in_db - 3,
               missing_recordings: @expected_in_db,
               total_birds: @expected_in_db
             }
    end

    test "filters by region when provided as an argument", %{services: services, bypass: bypass} do
      species_codes =
        "test/mock_data/region_codes/US-NC-067.json"
        |> File.read!()
        |> Jason.decode!()
        |> Enum.take(10)
        |> Jason.encode!()

      Bypass.expect(bypass, fn conn ->
        Plug.Conn.resp(conn, 200, species_codes)
      end)

      assert Counts.get(services, %{region: "US-NC-067"}) === %Counts{
               data_folder_bytes: 128,
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
    |> File.touch!()
  end
end
