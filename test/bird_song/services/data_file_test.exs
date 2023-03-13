defmodule BirdSong.Services.DataFileTest.FakeService do
  use GenServer
  alias BirdSong.Services.DataFile.Data

  def data_folder_path(%Data{service_instance: instance}) do
    GenServer.call(instance, :tmp_dir)
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

  alias BirdSong.TestHelpers
  alias BirdSong.{Services.Ebird, Services.DataFile}
  alias __MODULE__.FakeService
  alias DataFile.Data

  @bird_without_existing_file %Bird{common_name: "Giant Dodo", sci_name: "Dodo dodo"}
  @bird_with_existing_file @eastern_bluebird
  @good_response %HTTPoison.Response{status_code: 200, body: ~s({message: "hello"})}
  @good_data %Data{
    bird: @bird_without_existing_file,
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
          {:ok, service}

        %{} ->
          FakeService.start_link(
            tmp_dir: tmp_dir,
            name: test,
            use_correct_folder?: use_correct_folder?
          )
      end

    DataFile.register_listener(instance)

    data = %{@good_data | bird: bird, service: service, service_instance: service_instance}

    on_exit(fn ->
      Logger.configure(level: prev_level)
      remove_generated_files(service, bird, data)
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

      assert message ===
               {:ok, data |> Map.from_struct() |> Map.merge(%{written?: true})}

      assert File.ls(tmp_dir) === {:ok, ["Giant_Dodo.json"]}
    end

    test "logs a message when write is successful", %{instance: instance, data: data} do
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
            " bird=Giant Dodo",
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
                |> Map.merge(%{written?: false, error: :write_error, reason: :enoent})}
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
                   "bird=Giant Dodo",
                   "error=write_error",
                   "reason=enoent",
                   "service=Elixir.BirdSong.Services.DataFileTest.FakeService",
                   "written?=false"
                 ],
                 " "
               )
    end

    test "returns error for Ebird", %{instance: instance} do
      assert DataFile.write(%{@good_data | service: Ebird}, instance) ===
               {:error, :forbidden_service}

      refute_receive {DataFile, _}
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

    test "returns error if response is bad", %{instance: instance} do
      expected = {:error, :bad_response}

      assert @good_data
             |> Map.put(:response, {:ok, %{@good_response | status_code: 404}})
             |> DataFile.write(instance) === expected

      assert @good_data
             |> Map.put(:response, {:error, %HTTPoison.Error{}})
             |> DataFile.write(instance) === expected
    end

    @tag service: XenoCanto
    test "works for XenoCanto service", %{data: data, instance: instance} do
      assert DataFile.read(data) === {:error, :enoent}
      DataFile.write(data, instance)
      assert_receive {DataFile, {:ok, %{}}}
      assert {:ok, _} = DataFile.read(data)
    end
  end

  describe "&read/1" do
    @tag service: XenoCanto
    @tag use_existing_file?: true
    test "returns {:ok, string} when read is successful", %{
      data:
        %Data{
          service: XenoCanto,
          bird: @bird_with_existing_file
        } = data
    } do
      assert data |> DataFile.data_file_path() |> File.exists?()
      assert {:ok, "" <> _} = DataFile.read(data)
    end
  end

  def remove_generated_files(FakeService, %Bird{}, %Data{}) do
    File.rm_rf!("tmp")
  end

  def remove_generated_files(service, bird, %Data{} = data)
      when is_atom(service) and bird === @bird_without_existing_file do
    DataFile.remove(data)
  end

  def remove_generated_files(service, %Bird{}, %Data{}) when is_atom(service) do
    :ok
  end
end
