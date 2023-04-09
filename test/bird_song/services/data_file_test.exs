defmodule BirdSong.Services.DataFileTest.FakeService do
  use GenServer

  alias BirdSong.{
    Bird,
    Services.DataFile.Data,
    Services.Service
  }

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    {:ok, pid} = GenServer.start_link(__MODULE__, opts, name: name)
    pid
  end

  def init(opts) do
    opts = Enum.into(opts, %{})

    send(self(), :create_data_folder)

    {:ok, opts}
  end

  def data_folder_path(%Service{whereis: whereis}) do
    GenServer.call(whereis, :data_folder_path)
  end

  def handle_call(:data_folder_path, _from, state) do
    {:reply, instance_data_folder_path(state), state}
  end

  def handle_info(:create_data_folder, %{use_correct_folder?: false} = state) do
    {:noreply, state}
  end

  def handle_info(:create_data_folder, %{} = state) do
    state
    |> instance_data_folder_path()
    |> File.mkdir_p()

    {:noreply, state}
  end

  defp instance_data_folder_path(%{} = state) do
    state
    |> get_parent_folder()
    |> Path.join("fake_service")
  end

  defp get_parent_folder(%{use_correct_folder?: false}), do: "fake_folder"
  defp get_parent_folder(%{use_correct_folder?: true, tmp_dir: tmp_dir}), do: tmp_dir
end

defmodule BirdSong.Services.DataFileTest do
  use ExUnit.Case
  use BirdSong.MockDataAttributes
  import BirdSong.TestSetup

  alias BirdSong.{
    Services.Ebird,
    Services.DataFile,
    Services.Service,
    TestHelpers
  }

  alias __MODULE__.FakeService
  alias DataFile.Data

  @bird_without_existing_file %Bird{common_name: "Giant Dodo", sci_name: "Dodo dodo"}
  @bird_with_existing_file @eastern_bluebird
  @good_response %HTTPoison.Response{status_code: 200, body: ~s({message: "hello"})}

  @moduletag :tmp_dir
  @moduletag capture_log: true
  @moduletag seed_services?: false

  # TODO: these tests are broken and need to be fixed
  @moduletag :skip

  setup [:setup_bypass, :make_tmp_dir_path_relative, :start_throttler]

  setup %{} = tags do
    prev_level = Logger.level()
    name = Map.get(tags, :instance_name)

    service =
      tags
      |> Map.put_new(:service, FakeService)
      |> Map.put_new(:use_correct_folder?, true)
      |> start_service()

    data_folder_path = service.module.data_folder_path(service)

    {:ok, instance} = DataFile.start_link(name: name, data_folder_path: data_folder_path)
    DataFile.register_listener(instance)

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
       service: service
     },
     instance: instance}
  end

  describe "&write/1" do
    @tag service: FakeService
    test "sends {:ok, %{}} when write is successful", %{
      instance: instance,
      tmp_dir: tmp_dir,
      data: data
    } do
      assert File.ls(tmp_dir) === {:ok, ["fake_service"]}
      assert DataFile.write(data, instance) === :ok
      assert File.ls(tmp_dir) === {:ok, ["fake_service"]}

      assert_receive {DataFile, message}
      expected_path = expected_file_path(tmp_dir, "fake_service")
      assert {:ok, %{written?: true, path: ^expected_path}} = message

      assert tmp_dir |> Path.join("fake_service") |> File.ls() === {:ok, ["Giant_Dodo.json"]}
    end

    test "logs a message when write is successful", %{
      instance: instance,
      data: data,
      tmp_dir: tmp_dir
    } do
      Logger.configure(level: :info)

      [log] =
        ExUnit.CaptureLog.capture_log(fn ->
          assert DataFile.write(data, instance) === :ok
          assert_receive {DataFile, {:ok, %{written?: true}}}
        end)
        |> TestHelpers.parse_logs()

      expected =
        Enum.join(
          [
            " [BirdSong.Services.DataFile]",
            "path=" <> (tmp_dir |> expected_file_path("fake_service") |> inspect()),
            "service=BirdSong.Services.DataFileTest.FakeService",
            "written?=true"
          ],
          " "
        )

      assert [
               _,
               ^expected
             ] = String.split(log, "[info]")
    end

    @tag use_correct_folder?: false
    test "sends {:error, _} when write is not successful", %{instance: instance, data: data} do
      data_folder = apply(data.service.module, :data_folder_path, [data.service])
      assert data_folder === "fake_folder/fake_service"
      assert File.ls(data_folder) === {:error, :enoent}
      assert DataFile.write(data, instance) === :ok
      assert_receive {DataFile, message}
      assert File.ls(data_folder) === {:error, :enoent}

      assert message ===
               {:error,
                data
                |> Map.from_struct()
                |> Map.merge(%{
                  written?: false,
                  error: :write_error,
                  reason: :enoent,
                  path: expected_file_path("fake_folder", "fake_service")
                })}
    end

    @tag use_correct_folder?: false
    test "logs a warning when write is not successful", %{instance: instance, data: data} do
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert DataFile.write(data, instance) === :ok
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
                   "path=" <> inspect("fake_folder/fake_service/Giant_Dodo.json"),
                   "reason=" <> inspect(:enoent),
                   "service=BirdSong.Services.DataFileTest.FakeService",
                   "written?=false"
                 ],
                 " "
               )
    end

    test "returns error if server is not running", %{instance: instance, data: data} do
      assert is_pid(instance)
      assert :ok = GenServer.stop(instance)
      assert DataFile.write(data, instance) === {:error, {:not_alive, instance}}

      refute_receive {DataFile, _}
    end

    test "throws error if response is bad", %{data: data, instance: instance} do
      data
      |> Map.replace!(:response, {:ok, %{@good_response | status_code: 404}})
      |> DataFile.write(instance)

      assert_receive {DataFile, {:error, %{written?: false, error: :bad_response}}}

      data
      |> Map.put(:response, {:error, %HTTPoison.Error{}})
      |> DataFile.write(instance)

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

    @tag service: Ebird.Recordings
    test "works for Ebird.Recordings service", tags do
      assert_works_for_service(tags)
    end
  end

  describe "&read/1" do
    @tag service: Ebird.Recordings
    @tag use_existing_file?: true
    @tag tmp_dir: false
    test "returns {:ok, string} when read is successful", %{
      data:
        %Data{
          request: @bird_with_existing_file
        } = data,
      instance: instance
    } do
      file = GenServer.call(instance, {:data_file_path, data})
      assert file === "data/recordings/ebird/Eastern_Bluebird.json"
      assert File.exists?(file)
      assert {:ok, "" <> _} = DataFile.read(data, instance)
    end
  end

  defp assert_works_for_service(%{data: data, tmp_dir: tmp_dir}) do
    df_instance =
      data.service.whereis
      |> GenServer.call(:state)
      |> Map.fetch!(:data_file_instance)

    assert is_pid(df_instance)
    path = Service.data_folder_path(data.service)
    assert path =~ tmp_dir

    full_file_path =
      path
      |> Path.join(Service.data_file_name(data.service, data.request))
      |> Kernel.<>(".json")
      |> Path.relative_to_cwd()

    assert DataFile.read(data, df_instance) === {:error, {:enoent, full_file_path}}

    assert :ok = DataFile.write(data, df_instance)
    # assert_receive {DataFile, {:ok, %{written?: true}}}, 1_000
    assert {:ok, _} = DataFile.read(data, df_instance)
  end

  def expected_file_path(tmp_dir, folder_name) do
    tmp_dir
    |> Path.join(folder_name)
    |> Path.join("Giant_Dodo.json")
  end

  def make_tmp_dir_path_relative(%{tmp_dir: "" <> tmp_dir}) do
    {:ok, tmp_dir: Path.relative_to_cwd(tmp_dir)}
  end

  def make_tmp_dir_path_relative(%{}) do
    :ok
  end

  def start_service(%{
        service: FakeService,
        tmp_dir: tmp_dir,
        test: test,
        use_correct_folder?: use_correct_folder?
      }) do
    %Service{
      module: FakeService,
      whereis:
        FakeService.start_link(
          tmp_dir: tmp_dir,
          name: test,
          use_correct_folder?: use_correct_folder?
        )
    }
  end

  def start_service(%{service: service} = tags) when is_atom(service) do
    TestHelpers.start_service_supervised(service, tags)
  end
end
