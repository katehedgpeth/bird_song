defmodule BirdSong.Services.DataFileTest do
  use BirdSong.SupervisedCase
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Services.DataFile,
    Services.DataFile.Data,
    Services.Worker,
    TestHelpers
  }

  @bird_without_existing_file %Bird{common_name: "Giant Dodo", sci_name: "Dodo dodo"}
  @bird_with_existing_file @eastern_bluebird
  @good_response %{message: "hello"}

  @use_bad_folder [{DataFile, [parent_folder: "this_folder_doesnt_exist"]}]

  @moduletag :tmp_dir
  @moduletag capture_log: true
  @moduletag seed_services?: false
  @moduletag listen_to: [DataFile]

  setup %{} = tags do
    prev_level = Logger.level()

    worker = get_worker(Flickr, :PhotoSearch, tags)
    instance = get_service_name(DataFile, tags)

    bird =
      case tags do
        %{use_existing_file?: true} ->
          @bird_with_existing_file

        %{} ->
          @bird_without_existing_file
      end

    on_exit(fn ->
      Logger.configure(level: prev_level)
    end)

    {:ok,
     data: %Data{
       request: bird,
       response: {:ok, @good_response},
       worker: worker
     },
     instance: instance}
  end

  describe "&create_data_folder" do
    test "creates a new data folder for a worker", %{} = tags do
      assert %{instance: instance} = Map.take(tags, [:instance])
      assert Atom.to_string(instance) =~ Atom.to_string(tags[:test])
      state = Agent.get(instance, & &1)
      assert %DataFile{listeners: listeners} = state
      assert listeners === [self()]

      for {service, atom} <- [{Ebird, :Regions}, {Ebird, :RegionInfo}] do
        assert %Worker{instance_name: worker_name} = get_worker(service, atom, tags)
        assert Atom.to_string(worker_name) =~ Atom.to_string(tags[:test])

        assert_receive {DataFile,
                        %{message: :folder_created, worker: %Worker{instance_name: ^worker_name}}},
                       1_000
      end
    end
  end

  describe "&write/1" do
    setup [:await_all_folders]

    test "sends {:ok, %{}} when write is successful", %{
      data: data
    } do
      assert {:ok, %{message: "hello"}} = data.response

      assert Worker.data_folder_path(data.worker) === {:ok, "images/flickr"}
      assert {:ok, full_folder} = Worker.full_data_folder_path(data.worker)
      assert full_folder =~ "images/flickr"
      assert File.ls(full_folder) === {:ok, []}

      assert DataFile.write(data) === :ok

      assert_receive {DataFile, {:ok, message}}
      assert {:ok, expected_folder} = Worker.full_data_folder_path(data.worker)
      assert %{written?: true, path: received_path} = message
      assert received_path =~ expected_folder

      assert File.ls(expected_folder) === {:ok, ["Giant_Dodo.json"]}
    end

    test "logs a message when write is successful", %{
      data: data,
      tmp_dir: tmp_dir
    } do
      tmp_dir = Path.relative_to_cwd(tmp_dir)
      Logger.configure(level: :info)

      [log] =
        ExUnit.CaptureLog.capture_log(fn ->
          assert DataFile.write(data) === :ok
          assert_receive {DataFile, {:ok, %{written?: true}}}
        end)
        |> TestHelpers.parse_logs()

      expected =
        Enum.join(
          [
            " [BirdSong.Services.DataFile]",
            "path=" <> inspect(Path.join(tmp_dir, "images/flickr/Giant_Dodo.json")),
            "worker=BirdSong.Services.Flickr.PhotoSearch",
            "written?=true"
          ],
          " "
        )

      assert [
               _,
               ^expected
             ] = String.split(log, "[info]")
    end

    @tag opts: @use_bad_folder
    @tag await_all_folders?: false
    test "sends {:error, _} when write is not successful", %{} = tags do
      state = Agent.get(tags[:instance], & &1)
      assert state.parent_folder === "this_folder_doesnt_exist"
      assert File.ls(state.parent_folder) === {:error, :enoent}
      assert %Data{} = tags[:data]
      assert DataFile.write(tags[:data]) === :ok
      assert_receive {DataFile, message}

      assert message ===
               {:error,
                tags[:data]
                |> Map.from_struct()
                |> Map.merge(%{
                  written?: false,
                  error: :write_error,
                  reason: :enoent,
                  path: "this_folder_doesnt_exist/images/flickr/Giant_Dodo.json"
                })}
    end

    @tag opts: @use_bad_folder
    @tag await_all_folders?: false
    test "logs a warning when write is not successful", %{data: data} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert DataFile.write(data) === :ok
          assert_receive {DataFile, _}
        end)
        |> TestHelpers.parse_logs()

      assert [log] = log

      assert [
               _,
               log
             ] = String.split(log, " [warning] ", trim: true)

      assert log ===
               Enum.join(
                 [
                   "[BirdSong.Services.DataFile]",
                   "error=" <> inspect(:write_error),
                   "path=" <> inspect("this_folder_doesnt_exist/images/flickr/Giant_Dodo.json"),
                   "reason=" <> inspect(:enoent),
                   "worker=BirdSong.Services.Flickr.PhotoSearch",
                   "written?=false"
                 ],
                 " "
               )
    end

    test "does not accept raw HTTPoison responses", %{
      data: data
    } do
      assert_raise FunctionClauseError, fn ->
        data
        |> Map.replace!(
          :response,
          {:ok, %HTTPoison.Response{status_code: 200, body: Jason.encode!(@good_response)}}
        )
        |> DataFile.write()
      end
    end

    test "throws error if response is bad", %{data: data} do
      data
      |> Map.replace!(:response, {:error, %HTTPoison.Response{status_code: 404}})
      |> DataFile.write()

      assert_receive {DataFile, {:error, %{written?: false, error: :bad_response}}}

      data
      |> Map.put(:response, {:error, %HTTPoison.Error{}})
      |> DataFile.write()

      assert_receive {DataFile, {:error, %{written?: false, error: :bad_response}}}
    end

    @tag service: XenoCanto
    test "works for XenoCanto service", tags do
      assert_works_for_service(tags)
    end

    @tag service: Flickr
    test "works for Flickr service", tags do
      assert_works_for_service(tags)
    end

    @tag service: MacaulayLibrary.Recordings
    test "works for MacaulayLibrary.Recordings service", tags do
      assert_works_for_service(tags)
    end
  end

  describe "&read/1" do
    @tag service: MacaulayLibrary.Recordings
    @tag use_existing_file?: true
    @tag tmp_dir: false
    test "returns {:ok, string} when read is successful", %{
      data:
        %Data{
          request: @bird_with_existing_file
        } = data
    } do
      assert {:ok, file} = DataFile.data_file_path(data)
      assert file === "data/images/flickr/Eastern_Bluebird.json"
      assert File.exists?(file)
      assert {:ok, "" <> _} = DataFile.read(data)
    end
  end

  defp assert_works_for_service(%{data: %Data{} = data, tmp_dir: tmp_dir}) do
    tmp_dir = Path.relative_to_cwd(tmp_dir)
    assert {:ok, "" <> folder_path} = Worker.full_data_folder_path(data.worker)
    assert folder_path =~ tmp_dir

    assert {:ok, "" <> file_path} = DataFile.data_file_path(data)
    assert file_path =~ tmp_dir

    assert DataFile.read(data) === {:error, {:enoent, file_path}}

    assert DataFile.write(data) === :ok
    assert_receive {DataFile, {:ok, %{written?: true}}}, 1_000
    assert {:ok, "" <> _} = DataFile.read(data)
  end

  defp await_all_folders(%{await_all_folders?: false}) do
    :ok
  end

  defp await_all_folders(%{tmp_dir: tmp_dir} = tags) do
    for {service, atom} <- [
          {Ebird, :Regions},
          {Ebird, :RegionInfo},
          {Ebird, :RegionSpeciesCodes},
          {MacaulayLibrary, :Recordings},
          {Flickr, :PhotoSearch}
        ] do
      assert %Worker{instance_name: name} = get_worker(service, atom, tags)

      assert_receive {
        DataFile,
        %{
          message: :folder_created,
          worker: %Worker{instance_name: ^name}
        }
      }
    end

    assert {:ok, folders} = File.ls(tmp_dir)

    assert MapSet.new(folders) ===
             MapSet.new([
               "images",
               "recordings",
               "regions",
               "region_species_codes",
               "region_info"
             ])

    :ok
  end

  # defp start_service(%{
  #        worker: FakeWorker,
  #        tmp_dir: tmp_dir,
  #        test: test,
  #        use_correct_folder?: use_correct_folder?
  #      }) do
  #   _ =
  #     start_link_supervised!(
  #       {FakeWorker,
  #        [
  #          tmp_dir: tmp_dir,
  #          name: test,
  #          use_correct_folder?: use_correct_folder?
  #        ]}
  #     )

  #   %Worker{
  #     atom: :FakeWorker,
  #     instance_name: Module.concat(test, :FakeWorker),
  #     module: FakeWorker,
  #     parent: %Service{name: test, module: __MODULE__}
  #   }
  # end

  # defp start_service(%{worker: worker} = tags) when is_atom(worker) do
  #   start_supervised!({FakeWorker, Keyword.new(tags)})
  # end
end
