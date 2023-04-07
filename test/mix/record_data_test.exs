defmodule Mix.Tasks.RecordDataTest do
  use BirdSong.MockApiCase
  import BirdSong.TestSetup

  alias BirdSong.{
    Services.DataFile,
    Services.XenoCanto,
    Services.Flickr,
    TestHelpers,
    MockServer
  }

  alias Mix.Tasks.{RecordData.Config, RecordData}

  @moduletag :tmp_dir

  describe "&run/1" do
    @tag expect: &MockServer.success_response/1
    test "fetches data from image and recording services", %{services: services} do
      bird = BirdSong.Repo.get_by(Bird, common_name: "Wilson's Warbler")
      assert %Bird{} = bird

      TestHelpers.do_for_services(services, fn service ->
        assert {:error, {:enoent, _}} =
                 DataFile.read(%DataFile.Data{service: service, request: bird})
      end)

      assert RecordData.run(["--bird=Wilson's_Warbler"], services) === :ok

      assert_receive {:start_request, %{module: XenoCanto}}
      assert_receive {:start_request, %{module: Flickr}}
      assert_receive {:end_request, %{module: XenoCanto}}
      assert_receive {:end_request, %{module: Flickr}}

      assert {:ok, _} = Service.read_from_disk(services.recordings, bird)
      assert {:ok, _} = Service.read_from_disk(services.images, bird)
    end
  end

  @tag use_mock_routes?: false
  test "&Config.parse/2", %{services: services, tmp_dir: tmp_dir} do
    assert %Config{} === %{
             __struct__: Config,
             birds: [],
             seed_taxonomy?: false,
             taxonomy_file: nil,
             overwrite_files?: false,
             services: nil
           }

    assert Config.parse(["--taxonomy-file=" <> tmp_dir], services) === %Config{
             taxonomy_file: tmp_dir,
             services: services
           }

    assert Config.parse(["--overwrite"], services) === %Config{
             overwrite_files?: true,
             services: services
           }

    eastern_bluebird = BirdSong.Repo.get_by(Bird, common_name: "Eastern Bluebird")

    assert Config.parse(["--bird=Eastern_Bluebird"], services) === %Config{
             services: services,
             birds: [eastern_bluebird]
           }

    assert_raise RuntimeError, fn ->
      Config.parse(["--overwrite-files"], services)
    end
  end
end
