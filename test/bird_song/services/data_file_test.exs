defmodule BirdSong.Services.DataFileTest.FakeService do
  use GenServer

  alias BirdSong.{
    Bird,
    Services.DataFile.Data,
    Services.Service
  }

  def data_folder_path(%Service{whereis: pid}) do
    GenServer.call(pid, :tmp_dir)
  end

  def data_file_name(%Bird{common_name: common_name}) do
    common_name
  end

  def start_link(opts) do
    {name, opts} = Keyword.pop!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    {:ok, Enum.into(opts, %{})}
  end

  def handle_call(:tmp_dir, _from, state) do
    {:reply, instance_data_folder_path(state), state}
  end

  defp instance_data_folder_path(%{use_correct_folder?: false}), do: "data/fake_folder"
  defp instance_data_folder_path(%{use_correct_folder?: true, tmp_dir: tmp_dir}), do: tmp_dir
end

defmodule BirdSong.Services.DataFileTest do
  use ExUnit.Case
  use BirdSong.MockDataAttributes

  alias BirdSong.MockApiCase
  alias BirdSong.TestHelpers

  alias BirdSong.{
    Services.Ebird,
    Services.DataFile,
    Services.Service
  }

  alias __MODULE__.FakeService
  alias DataFile.Data

  @bird_without_existing_file %Bird{common_name: "Giant Dodo", sci_name: "Dodo dodo"}
  @bird_with_existing_file @eastern_bluebird
  @good_response %HTTPoison.Response{status_code: 200, body: ~s({message: "hello"})}
  @good_data %Data{
    request: @bird_without_existing_file,
    response: {:ok, @good_response}
  }

  @moduletag :tmp_dir
  @moduletag capture_log: true

  setup %{test: test, tmp_dir: tmp_dir} = tags do
    prev_level = Logger.level()
    name = Map.get(tags, :instance_name)
    use_correct_folder? = Map.get(tags, :use_correct_folder?, true)
    {:ok, instance} = DataFile.start_link(name: name)

    service = Map.get(tags, :service, FakeService)

    bird =
      case tags do
        %{use_existing_file?: true} ->
          @bird_with_existing_file

        %{} ->
          @bird_without_existing_file
      end

    {:ok, service_instance} =
      case tags do
        %{service: service} when is_atom(service) ->
          MockApiCase.start_service_supervised(service, tags)

        %{} ->
          FakeService.start_link(
            tmp_dir: tmp_dir,
            name: test,
            use_correct_folder?: use_correct_folder?
          )
      end

    assert is_pid(service_instance)

    DataFile.register_listener(instance)

    data = %{
      @good_data
      | request: bird,
        service: %Service{name: service, whereis: service_instance}
    }

    on_exit(fn ->
      Logger.configure(level: prev_level)
      MockApiCase.clean_up_tmp_folders(tags)
    end)

    {:ok, instance: instance, data: data}
  end

  describe "&write/1" do
    test "sends {:ok, %{}} when write is successful", %{
      instance: instance,
      tmp_dir: tmp_dir,
      data: data
    } do
      assert DataFile.write(data, instance) === :ok

      assert_receive {DataFile, message}
      expected_path = expected_file_path(tmp_dir)
      assert {:ok, %{written?: true, path: ^expected_path}} = message

      assert File.ls(tmp_dir) === {:ok, ["Giant Dodo.json"]}
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
            " path=" <> expected_file_path(tmp_dir),
            "service=Elixir.BirdSong.Services.DataFileTest.FakeService",
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
      assert DataFile.write(data, instance) === :ok
      assert_receive {DataFile, message}

      assert message ===
               {:error,
                data
                |> Map.from_struct()
                |> Map.merge(%{
                  written?: false,
                  error: :write_error,
                  reason: :enoent,
                  path: expected_file_path("data/fake_folder")
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
                   "error=write_error",
                   "path=data/fake_folder/Giant Dodo.json",
                   "reason=enoent",
                   "service=Elixir.BirdSong.Services.DataFileTest.FakeService",
                   "written?=false"
                 ],
                 " "
               )
    end

    @tag instance_name: FakeService
    test "returns error if named server is not running" do
      whereis = GenServer.whereis(FakeService)
      assert is_pid(whereis)
      assert Process.alive?(whereis)
      assert :ok = GenServer.stop(FakeService)
      assert DataFile.write(@good_data, FakeService) === {:error, :not_alive}

      refute_receive {DataFile, _}
    end

    test "returns error if unnamed server is not running", %{instance: instance} do
      whereis = GenServer.whereis(instance)
      assert is_pid(whereis)
      assert :ok = GenServer.stop(instance)
      assert DataFile.write(@good_data, instance) === {:error, :not_alive}

      refute_receive {DataFile, _}
    end

    test "throws error if response is bad", %{instance: instance} do
      assert_raise FunctionClauseError, fn ->
        @good_data
        |> Map.put(:response, {:ok, %{@good_response | status_code: 404}})
        |> DataFile.write(instance)
      end

      assert_raise FunctionClauseError, fn ->
        @good_data
        |> Map.put(:response, {:error, %HTTPoison.Error{}})
        |> DataFile.write(instance)
      end
    end

    @tag service: XenoCanto
    test "works for XenoCanto service", tags do
      assert_works_for_service(tags)
    end

    @tag service: Flickr
    test "works for Flickr service", tags do
      assert_works_for_service(tags)
    end

    @tag service: Ebird
    test "works for Ebird service", tags do
      tags =
        Map.update!(tags, :data, &Map.replace!(&1, :request, {:recent_observations, "US-NC-067"}))

      data = Map.fetch!(tags, :data)
      assert Path.join(tags[:tmp_dir], "US-NC-067.json") =~ DataFile.data_file_path(data)
      assert_works_for_service(tags)
    end
  end

  describe "&read/1" do
    @tag service: XenoCanto
    @tag use_existing_file?: true
    @tag tmp_dir: false
    test "returns {:ok, string} when read is successful", %{
      data:
        %Data{
          request: @bird_with_existing_file
        } = data
    } do
      file = DataFile.data_file_path(data)
      assert file === "data/recordings/Eastern_Bluebird.json"
      assert File.exists?(file)
      assert {:ok, "" <> _} = DataFile.read(data)
    end
  end

  defp assert_works_for_service(%{data: data, instance: instance, tmp_dir: tmp_dir}) do
    assert apply(data.service.name, :data_folder_path, [data.service]) === tmp_dir
    assert DataFile.read(data) === {:error, :enoent}
    assert :ok = DataFile.write(data, instance)
    assert_receive {DataFile, {:ok, %{}}}
    assert {:ok, _} = DataFile.read(data)
  end

  def expected_file_path(tmp_dir) do
    tmp_dir
    |> Path.relative_to_cwd()
    |> Path.join("Giant Dodo.json")
  end
end
