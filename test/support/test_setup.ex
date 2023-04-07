defmodule BirdSong.TestSetup do
  require ExUnit.Assertions
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    Bird,
    Services,
    Services.Service,
    TestHelpers
  }

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

  def start_services(%{} = tags) do
    tags = Map.put_new(tags, :bypass, Bypass.open())

    setup_route_mocks(tags)

    images_module = Map.get(tags, :images_service, Flickr)
    recordings_module = Map.get(tags, :recordings_module, Ebird.Recordings)
    observations_module = Map.get(tags, :observations_service, Ebird.Observations)
    region_species_codes_module = Map.get(tags, :region_species_code_module, Ebird.RegionCodes)

    [recordings_service, images_service, observations_service, region_species_code_service] =
      Enum.map(
        [
          recordings_module,
          images_module,
          observations_module,
          region_species_codes_module
        ],
        &TestHelpers.start_service_supervised(&1, tags)
      )

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
        observations: observations_service,
        region_codes: region_species_code_service,
        timeout: Map.get(tags, :timeout, 1_000)
      }
    }
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
end
