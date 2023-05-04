defmodule BirdSong.TestSetup do
  require ExUnit.Assertions
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Bird,
    TestHelpers
  }

  def seed_from_mock_taxonomy(%{seed_data?: false}) do
    :ok
  end

  def seed_from_mock_taxonomy(%{} = tags) do
    tags
    |> Map.put_new(:taxonomy_file, TestHelpers.mock_file_path("mock_taxonomy"))
    |> seed_from_taxonomy()
  end

  def seed_from_taxonomy(%{} = tags) do
    ExUnit.Assertions.assert(
      {:ok, [%Bird{} | _]} =
        tags
        |> Map.fetch!(:taxonomy_file)
        |> Ebird.Taxonomy.read_data_file()
        |> Ebird.Taxonomy.seed()
    )

    :ok
  end

  def clean_up_tmp_folder_on_exit(%{tmp_dir: "" <> tmp_dir}) do
    ExUnit.Callbacks.on_exit(fn ->
      tmp_dir
      |> Path.join("..")
      |> File.rm_rf!()
    end)

    :ok
  end

  def clean_up_tmp_folder_on_exit(%{}), do: :ok

  def copy_seed_files_to_tmp_folder(%{tmp_folder: tmp_folder}) do
    for folder <- ["images", "recordings"] do
      {:ok, [_ | _]} =
        "data"
        |> Path.join(folder)
        |> File.cp_r(tmp_folder)
    end

    :ok
  end

  def copy_seed_files_to_tmp_folder(%{}) do
    :ok
  end
end
