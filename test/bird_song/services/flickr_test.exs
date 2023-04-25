defmodule BirdSong.Services.FlickrTest do
  use BirdSong.DataCase
  use BirdSong.MockDataAttributes

  import BirdSong.TestSetup, only: [setup_bypass: 1, start_service_supervisor!: 1]

  alias BirdSong.{
    Services.DataFile,
    Services.Flickr,
    Services.Service,
    TestHelpers
  }

  @bird @carolina_wren

  @moduletag :tmp_dir
  @moduletag copy_files?: true
  @moduletag service: :Flickr

  setup_all do
    service = Flickr.get_instance_child(Flickr, :PhotoSearch)
    assert %Service{} = service
    df_instance = Flickr.PhotoSearch.data_file_instance(service)

    {:ok, "" <> raw_images} =
      DataFile.read(%DataFile.Data{service: service, request: @bird}, df_instance)

    {:ok, raw_images: raw_images}
  end

  setup [:setup_bypass, :start_service_supervisor!]

  setup tags do
    service = Flickr.get_instance_child(tags[:test], :PhotoSearch)

    if Map.fetch!(tags, :copy_files?) do
      expected_path = Flickr.PhotoSearch.data_folder_path(service)
      [_ | _] = File.cp_r!("data/images/flickr", expected_path)
    end

    {:ok, service: service}
  end

  describe "&get_image/1" do
    @tag copy_files?: false
    test "returns {:ok, %Flickr.Response{}} when cache is empty and data file does not exist, so API is called",
         %{
           bypass: bypass,
           raw_images: raw_images,
           service: %Service{whereis: whereis}
         } do
      assert Flickr.PhotoSearch.get_from_cache(@bird, whereis) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, whereis) === :not_found

      Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, raw_images))

      assert {:ok, response} = Flickr.PhotoSearch.get(@bird, whereis)

      assert %Flickr.Response{
               images: [%Flickr.Photo{url: "https://live.staticflickr.com" <> path} | _]
             } = response

      assert String.ends_with?(path, ".jpg")
    end

    test "returns {:ok, %Flickr.Response{}} when cache is not populated but data file exists", %{
      service: %Service{whereis: whereis}
    } do
      assert Flickr.PhotoSearch.get_from_cache(@bird, whereis) === :not_found

      assert {:ok, %Flickr.Response{} = response} =
               Flickr.PhotoSearch.parse_from_disk(@bird, whereis)

      assert {:ok, ^response} = Flickr.PhotoSearch.get_images(@bird, whereis)
    end

    @tag copy_files?: false
    test "returns {:ok, %Flickr.Response{}} when cache is populated", %{
      bypass: bypass,
      raw_images: raw_images,
      service: service
    } do
      assert Flickr.PhotoSearch.get_from_cache(@bird, service.whereis) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, service.whereis) === :not_found
      Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, raw_images))
      assert {:ok, response} = Flickr.PhotoSearch.get(@bird, service)
      assert {:ok, ^response} = Flickr.PhotoSearch.get_from_cache(@bird, service.whereis)
      # expect_once should throw an error if the API is called again
      assert {:ok, ^response} = Flickr.PhotoSearch.get(@bird, service)
    end

    @tag copy_files?: false
    test "returns {:error, {:not_found, path}} when API returns 404", %{
      bypass: bypass,
      service: service
    } do
      assert Flickr.PhotoSearch.get_from_cache(@bird, service.whereis) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, service.whereis) === :not_found

      Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 404, "That page does not exist") end)

      assert {:error,
              {:not_found,
               bypass
               |> TestHelpers.mock_url()
               |> Path.join(Flickr.PhotoSearch.endpoint(@bird))}} ===
               Flickr.PhotoSearch.get(@bird, service)
    end
  end
end
