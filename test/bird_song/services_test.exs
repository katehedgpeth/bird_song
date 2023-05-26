defmodule BirdSong.ServicesTest do
  use BirdSong.SupervisedCase

  alias BirdSong.Services.Supervisor.ForbiddenExternalURLError

  alias Services.{
    DataFile,
    Ebird,
    Flickr,
    MacaulayLibrary,
    RequestThrottler,
    ThrottledCache.State,
    Worker
  }

  @moduletag :capture_log
  @moduletag :tmp_dir

  @tag use_mock_routes?: false
  test "all/0 returns running instances without raising an error" do
    services = Services.all()
    assert %Services{} = services
  end

  describe "start_link" do
    @describetag start_services?: false
    def test_start_link_in_env(env, tags) do
      assert {:error, {{:already_started, _}, _}} = start_supervised({Services, env: env})

      assert {:ok, _pid} = start_supervised({Services, env: env, name: tags[:test]})

      assert started = Services.all(tags[:test])
      assert %Services{} = started

      for service <- [Ebird, Flickr, MacaulayLibrary] do
        request_throttler = get_worker(service, :RequestThrottler, tags)

        state =
          request_throttler
          |> Worker.call(:state)
          |> Map.from_struct()

        assert Map.keys(state) === [
                 :base_url,
                 :current_request,
                 :name,
                 :queue,
                 :queue_size,
                 :throttle_ms,
                 :throttled?,
                 :unthrottle_ref,
                 :worker
               ],
               """
               request_throttler: #{inspect(request_throttler.instance_name)}
               env: #{env}
               keys: #{inspect(Map.keys(state))}
               """

        assert {:error, %ForbiddenExternalURLError{}} = state[:base_url]
        assert state[:name] === nil
        assert state[:queue] === {[], []}
        assert state[:queue_size] === 0
        assert state[:throttle_ms] === 1_000
        assert state[:throttled?] === false
        assert %Worker{} = state[:worker]
        assert is_reference(state[:unthrottle_ref])
        assert state[:current_request] === nil
      end

      for service <- [:ebird, :recordings, :images] do
        service = Map.fetch!(started, service)

        for {atom, worker} <-
              service
              |> Map.from_struct()
              |> Enum.reject(&(elem(&1, 0) === :name)) do
          state =
            worker
            |> Worker.call(:state)
            |> Map.from_struct()

          assert Map.keys(state) === [
                   :ets_name,
                   :ets_opts,
                   :ets_table,
                   :listeners,
                   :requests_ets,
                   :supervisors,
                   :worker,
                   :write_responses_to_disk?
                 ],
                 """
                 worker: #{inspect(worker.instance_name)}
                 keys: #{inspect(Map.keys(state))}
                 """

          assert is_atom(atom)

          for {key, val} <- state do
            case {key, worker} do
              {:ets_name, worker} ->
                expected =
                  worker.module
                  |> Module.split()
                  |> Enum.slice(2..3)
                  |> Module.concat()
                  |> Macro.underscore()
                  |> String.replace("/", "_")
                  |> String.to_existing_atom()

                assert val === expected,
                       ":ets_name for #{atom} is #{inspect(val)}, not #{inspect(expected)}"

              {:ets_opts, _} ->
                assert val === []

              {:ets_table, _} ->
                assert val === nil

              {:listeners, _} ->
                assert val === []

              {:requests_ets, _} ->
                assert is_reference(val)

              {:supervisors, _} ->
                assert %State.Supervisors{ets: ets} = val
                assert is_pid(ets)

              {:worker, _} ->
                assert val === worker

              {:write_responses_to_disk?, _} ->
                assert val === false
            end
          end
        end
      end
    end

    test "when Mix.env() === :dev", tags do
      test_start_link_in_env(:dev, tags)
    end

    test "when Mix.env() === :prod", tags do
      test_start_link_in_env(:prod, tags)
    end

    test "when Mix.env() === :test", tags do
      test_start_link_in_env(:test, tags)
    end
  end

  describe "all/1" do
    test "from test name", %{test: test, tmp_dir: tmp_dir} do
      services = Services.all(test)
      assert %Services{} = services

      for {key, service} <- Map.from_struct(services) do
        case key do
          :data_file ->
            assert %DataFile{} = service
            assert service.parent_folder === tmp_dir

          supervisor when supervisor in [:ebird, :images, :recordings] ->
            :ok
        end
      end
    end

    test "from worker", %{tmp_dir: tmp_dir} = tags do
      worker = get_worker(Ebird, :Regions, tags)
      services = Services.all(worker)

      assert %Services{} = services
      assert services.data_file.parent_folder === tmp_dir
    end
  end

  describe "SupervisedCase" do
    test "starts all services supervised", %{test: test, tmp_dir: tmp_dir} do
      services = Services.all(test)
      assert %Services{} = services

      assert services |> Map.from_struct() |> Map.keys() === [
               :data_file,
               :ebird,
               :images,
               :recordings
             ]

      assert services.data_file === %DataFile{parent_folder: tmp_dir}
      assert %Ebird{} = services.ebird
      assert %MacaulayLibrary{} = services.recordings
      assert %Flickr{} = services.images

      for {module, key} <- [{Ebird, :ebird}, {MacaulayLibrary, :recordings}, {Flickr, :images}] do
        request_throttler =
          services
          |> Map.fetch!(key)
          |> Map.fetch!(:name)
          |> module.get_instance_child(:RequestThrottler)

        assert %Worker{} = request_throttler

        assert RequestThrottler.base_url(request_throttler) =~ "http://localhost:"
      end
    end

    test "data_folder_path option", %{test: test} = tags do
      assert {:ok, tmp_dir} = Map.fetch(tags, :tmp_dir)
      services = Services.all(test)
      assert %Ebird{} = services.ebird
      assert %Worker{} = services.ebird[:Observations]

      assert services.ebird[:Observations]
             |> Services.Ebird.Observations.data_folder_path() ===
               {:error, :never_write_to_disk}

      assert services.ebird[:Regions]
             |> Services.Ebird.Regions.data_folder_path() ===
               {:ok, Path.join([tmp_dir, "regions", "ebird"])}

      assert services.images[:PhotoSearch]
             |> Services.Flickr.PhotoSearch.data_folder_path() ===
               {:ok, Path.join([tmp_dir, "images", "flickr"])}
    end

    @tag use_bypass?: false
    @tag opts: [{Ebird, allow_external_calls?: true}]
    test "allow_external_calls option", tags do
      assert {:ok, [{Ebird, allow_external_calls?: true}]} = Map.fetch(tags, :opts)

      assert [base_url: expected, allow_external_calls?: true] =
               [
                 base_url: "https://api.ebird.org",
                 allow_external_calls?: true
               ]
               |> Services.Supervisor.parse_base_url()

      assert %URI{} = expected

      worker = get_worker(Ebird, :RequestThrottler, tags)
      state = Worker.call(worker, :state)

      assert state.base_url === expected
    end

    test "get_worker", %{test: test} = tags do
      assert %Services{} = Services.all(test)
      request_throttler = get_worker(Ebird, :RequestThrottler, tags)
      assert %Worker{} = request_throttler
      assert RequestThrottler.base_url(request_throttler) =~ "http://localhost"
    end
  end
end
