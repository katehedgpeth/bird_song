defmodule BirdSong.Services.WorkerTest do
  use BirdSong.SupervisedCase, async: true

  alias BirdSong.Services.{
    Worker
  }

  @tag use_bypass?: false
  describe "data_folder_path" do
    test "without tmp_dir", %{test: test} = tags do
      assert Map.fetch(tags, :tmp_dir) === :error
      services = BirdSong.Services.all(test)
      worker = services.ebird[:Regions]
      assert %Worker{} = worker

      assert Worker.data_folder_path(worker) === {:ok, "regions/ebird"}
      assert Worker.full_data_folder_path(worker) === {:ok, "data/regions/ebird"}
    end

    @tag :tmp_dir
    test "with tmp_dir", %{test: test} = tags do
      tmp_dir = Path.relative_to_cwd(tags[:tmp_dir])

      services = BirdSong.Services.all(test)
      worker = services.ebird[:Regions]
      assert %Worker{} = worker
      assert Worker.data_folder_path(worker) === {:ok, "regions/ebird"}
      assert Worker.full_data_folder_path(worker) === {:ok, Path.join(tmp_dir, "regions/ebird")}
    end
  end
end
