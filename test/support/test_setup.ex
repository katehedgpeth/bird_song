defmodule BirdSong.TestSetup do
  require ExUnit.Assertions
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Bird,
    Services,
    Services.RequestThrottler,
    Services.Service,
    TestHelpers
  }

  defmacro __using__(functions) do
    quote bind_quoted: [functions: functions] do
      use ExUnit.Case, async: true
      alias BirdSong.TestSetup
      :ok = TestSetup.verify_use_args(functions)

      @tag setup_functions: functions

      setup [:run_setup_functions]

      # ExUnit.Case.register_test(&__MODULE__.register_test/6)

      def register_test(mod, file, line, test_type, name, tags) do
        Module.put_attribute(
          BirdSong.Services.Supervisor,
          :registered_tests,
          %{mod: mod, file: file, line: line, test_type: test_type, name: name, tags: tags}
        )
      end

      defp run_setup_functions(tags) do
        TestSetup.run_setup_functions(tags)
      end
    end
  end

  def run_setup_functions(tags) do
    {setup_functions, tags} = Map.pop!(tags, :setup_functions)

    {:ok,
     Enum.reduce(setup_functions, tags, fn func, acc ->
       {:ok, new_tags} = apply(BirdSong.TestSetup, func, [acc])
       Map.merge(acc, Map.new(new_tags))
     end)}
  end

  def listen_to_services(%{services: %Services{} = services}) do
    TestHelpers.do_for_services(services, &listen_to_service/1)

    :ok
  end

  defp listen_to_service(%Service{module: module, whereis: whereis}) do
    apply(module, :register_request_listener, [whereis])
  end

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

  def set_tmp_data_folder(opts, tags) do
    case tags do
      %{tmp_dir: "" <> tmp_dir} -> Keyword.put(opts, :data_folder_path, tmp_dir)
      %{} -> opts
    end
  end

  def start_throttlers(%{} = tags) do
    {:ok, throttler: ebird} = start_throttler(tags)
    {:ok, throttler: macaulay} = start_throttler(tags)
    {:ok, throttler: flickr} = start_throttler(tags)

    {:ok,
     throttlers: %{
       ebird: ebird,
       macaulay: macaulay,
       flickr: flickr
     }}
  end

  @type throttler() :: %{
          base_url: String.t(),
          pid: pid(),
          bypass: Bypass.t()
        }

  @spec start_throttler(Map.t()) :: {:ok, throttler: pid()}
  def start_throttler(%{bypass: bypass} = tags) do
    url = TestHelpers.mock_url(bypass)

    {:ok, pid} =
      RequestThrottler.start_link(base_url: url, throttle_ms: Map.get(tags, :throttle_ms, 0))

    {:ok, throttler: pid}
  end

  def start_throttler(%{} = tags) do
    bypass = Bypass.open()

    {:ok, throttler: throttler} =
      tags
      |> Map.put(:bypass, bypass)
      |> start_throttler()

    {:ok, bypass: bypass, throttler: throttler}
  end

  def start_services(%{} = tags) do
    tags = Map.put_new(tags, :bypass, Bypass.open())

    setup_route_mocks(tags)

    images_module = Map.get(tags, :images_service, Flickr)
    recordings_module = Map.get(tags, :recordings_module, Ebird.Recordings)

    [recordings_service, images_service] =
      Enum.map(
        [
          recordings_module,
          images_module
        ],
        &TestHelpers.start_service_supervised(&1, tags)
      )

    {:ok, supervisor: %Service{}, service: ebird} =
      tags
      |> Map.update(:service, :Ebird, fn _ -> :Ebird end)
      |> start_service_supervisor!()

    bird =
      case Map.get(tags, :bird) do
        bird when bird in @mocked_birds -> bird
        nil -> nil
      end

    {
      :ok,
      bypass: Map.fetch!(tags, :bypass),
      services: %Services{
        bird: bird,
        images: images_service,
        recordings: recordings_service,
        ebird: ebird,
        timeout: Map.get(tags, :timeout, 1_000)
      }
    }
  end

  def start_service_supervisor!(%{test: test, service: service} = tags)
      when service in [:Ebird] do
    opts =
      []
      |> Keyword.put(:service_name, test)
      |> set_tmp_data_folder(tags)
      |> TestHelpers.get_base_url(tags)
      |> TestHelpers.get_throttle_ms_opt(tags)

    module = Module.concat([BirdSong.Services, service])
    whereis = ExUnit.Callbacks.start_supervised!({module, opts})

    test
    |> BirdSong.Services.Supervisor.instance_name(module)
    |> GenServer.whereis()
    |> is_pid()
    |> ExUnit.Assertions.assert()

    {:ok,
     supervisor: %Service{
       module: module,
       name: test,
       whereis: whereis
     },
     service: apply(module, :services, [test])}
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

  def setup_bypass(%{use_bypass: false}) do
    :ok
  end

  def setup_bypass(%{}) do
    {:ok, bypass: Bypass.open()}
  end

  @type bypass_generic_cb :: (Plug.Conn.t() -> Plug.Conn.t())
  @type bypass_path_cb :: {String.t(), String.t(), bypass_generic_cb()}

  @spec setup_route_mocks(%{
          required(:bypass) => Bypass.t(),
          optional(:expect_once) => bypass_generic_cb() | List.t(bypass_generic_cb()),
          optional(:expect) => bypass_generic_cb() | List.t(bypass_generic_cb()),
          optional(:stub) => bypass_path_cb() | List.t(bypass_path_cb()),
          optional(any) => any
        }) :: :ok
  def setup_route_mocks(%{use_mock_routes?: false}), do: :ok

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        expect_once: func
      })
      when is_function(func),
      do: Bypass.expect_once(bypass, func)

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        expect_once: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect_once(bypass, method, path, func)
        end)

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        expect: func
      })
      when is_function(func),
      do: Bypass.expect(bypass, func)

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        expect: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect(bypass, method, path, func)
        end)

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        stub: {"" <> method, "" <> path, func}
      })
      when is_function(func),
      do: Bypass.stub(bypass, method, path, func)

  def setup_route_mocks(%{
        bypass: %Bypass{} = bypass,
        stub: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.stub(bypass, method, path, func)
        end)

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

  def verify_use_args(funcs) when is_list(funcs) do
    funcs
    |> Enum.group_by(&is_setup_function?/1)
    |> Map.new()
    |> case do
      %{false: not_functions} ->
        raise_use_error(not_functions)

      %{} ->
        :ok
    end
  end

  def verify_use_args(not_func_list) do
    raise_use_error(not_func_list)
  end

  defp is_setup_function?(func) when is_atom(func) do
    Kernel.function_exported?(__MODULE__, func, 1)
  end

  defp raise_use_error(not_functions) do
    raise ArgumentError.exception(
            message: """


            use Helpers.TestSetup expected to get a list of names of
            setup functions to run, but these are not known functions:

            #{inspect(not_functions)}

            """
          )
  end
end
