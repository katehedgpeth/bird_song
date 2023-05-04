defmodule BirdSong.Services.FlickrTest do
  use BirdSong.SupervisedCase
  use BirdSong.DataCase
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Services.DataFile,
    Services.Flickr,
    Services.Worker,
    TestHelpers
  }

  @bird @carolina_wren

  @moduletag :tmp_dir
  @moduletag copy_files?: true
  @moduletag service: :Flickr

  setup_all do
    worker = Flickr.get_instance_child(:PhotoSearch)
    assert %Worker{instance_name: Flickr.PhotoSearch} = worker

    {:ok, "" <> raw_images} = DataFile.read(%DataFile.Data{worker: worker, request: @bird})

    {:ok, raw_images: raw_images}
  end

  setup tags do
    tmp_dir = Path.relative_to_cwd(tags[:tmp_dir])
    %{worker: worker, bypass: bypass} = get_worker_setup(Flickr, :PhotoSearch, tags)

    assert {:ok, path} = Worker.full_data_folder_path(worker)
    assert path === Path.join(tmp_dir, "images/flickr")

    case Map.get(tags, :copy_files?) do
      true ->
        assert [_ | _] = File.cp_r!("data/images/flickr", path)

      _ ->
        :ok
    end

    {:ok, worker: worker, bypass: bypass}
  end

  describe "&get_image/1" do
    @tag copy_files?: false
    test "returns {:ok, %Flickr.Response{}} when cache is empty and data file does not exist, so API is called",
         %{
           bypass: bypass,
           raw_images: raw_images,
           worker: worker
         } do
      assert %Bypass{} = bypass
      assert Flickr.PhotoSearch.get_from_cache(@bird, worker) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, worker) === :not_found

      Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, raw_images))

      assert {:ok, response} = Flickr.PhotoSearch.get(@bird, worker)

      assert %Flickr.Response{
               images: [%Flickr.Photo{url: "https://live.staticflickr.com" <> path} | _]
             } = response

      assert String.ends_with?(path, ".jpg")
    end

    test "returns {:ok, %Flickr.Response{}} when cache is not populated but data file exists", %{
      worker: worker
    } do
      assert Flickr.PhotoSearch.get_from_cache(@bird, worker) === :not_found

      assert {:ok, %Flickr.Response{} = response} =
               Flickr.PhotoSearch.parse_from_disk(@bird, worker)

      assert {:ok, ^response} = Flickr.PhotoSearch.get_images(@bird, worker)
    end

    @tag copy_files?: false
    test "returns {:ok, %Flickr.Response{}} when cache is populated",
         %{
           bypass: bypass,
           raw_images: raw_images,
           worker: worker
         } do
      assert %Bypass{} = bypass
      assert Flickr.PhotoSearch.get_from_cache(@bird, worker) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, worker) === :not_found
      Bypass.expect_once(bypass, &Plug.Conn.resp(&1, 200, raw_images))
      assert {:ok, response} = Flickr.PhotoSearch.get(@bird, worker)
      assert {:ok, ^response} = Flickr.PhotoSearch.get_from_cache(@bird, worker)
      # expect_once should throw an error if the API is called again
      assert {:ok, ^response} = Flickr.PhotoSearch.get(@bird, worker)
    end

    @tag copy_files?: false
    test "returns {:error, {:not_found, path}} when API returns 404", %{
      bypass: bypass,
      worker: worker
    } do
      assert %Bypass{} = bypass
      assert Flickr.PhotoSearch.get_from_cache(@bird, worker) === :not_found
      assert Flickr.PhotoSearch.get_from_cache(@bird, worker) === :not_found
      assert Flickr.PhotoSearch.parse_from_disk(@bird, worker) === :not_found

      Bypass.expect(bypass, fn conn -> Plug.Conn.resp(conn, 404, "That page does not exist") end)

      assert {:error,
              {:not_found,
               bypass
               |> TestHelpers.mock_url()
               |> Path.join(Flickr.PhotoSearch.endpoint(@bird))}} ===
               Flickr.PhotoSearch.get(@bird, worker)
    end
  end
end
