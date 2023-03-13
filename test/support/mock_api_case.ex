defmodule BirdSong.MockApiCase do
  @moduledoc """
  Handles boilerplate of setting up mocks for external APIs using Bypass.

  Expects all services to have a :base_url config under the :bird_song config.

  Use one of these tags to skip bypass setup:
    * `@tag use_bypass: false` will skip all bypass setup
    * `@tag use_mocks: false` will initialize bypass but skip setting up expects

  To use the mock setup process, the `:service` tag is always required. This specifies which services
  should have their `:base_url` config updated.
    * `@tag service: [ServiceName, OtherServiceName]`

  Also, one or more of the following tags is required to use the mock setup process:
    * `@tag expect_once: &Module.function/1`
    * `@tag expect_once: [{"" <> method, "" <> path, &Module.function/1}]`
    * `@tag expect: &Module.function/1`
    * `@tag expect: [{"" <> method, "" <> path, &Module.function/1}]`
    * `@tag stub: {"" <> method, "" <> path, &Module.function/1}`
    * `@tag stub: [{"" <> method, "" <> path, &Module.function/1}]`

  Other optional tags:
    * `@tag bird: %Bird{}` - use this to specify which bird the services should return data for.
    * `@tag recordings_service: ModuleName`
    * `@tag images_service: ModuleName`
  """
  use ExUnit.CaseTemplate
  use BirdSong.MockDataAttributes

  alias BirdSong.{
    TestHelpers,
    Services,
    Services.Service,
    Services.Ebird,
    Services.Flickr,
    Services.XenoCanto
  }

  using opts do
    quote location: :keep do
      if unquote(Keyword.get(opts, :use_data_case, true)) do
        use BirdSong.DataCase
      end

      require Logger
      import BirdSong.MockApiCase
      use BirdSong.MockDataAttributes
      alias BirdSong.{MockServer, TestHelpers, Services.Ebird}

      defp listen_to_services(%{services: %Services{} = services}) do
        do_for_services(services, &listen_to_service/1)

        :ok
      end

      defp listen_to_service(%Service{name: name, whereis: whereis}) do
        apply(name, :register_request_listener, [whereis])
      end

      def seed_from_mock_taxonomy(%{}) do
        assert {:ok, [%Services{} | _]} =
                 "mock_taxonomy"
                 |> TestHelpers.mock_file_path()
                 |> Ebird.Taxonomy.read_data_file()
                 |> Ebird.Taxonomy.seed()

        :ok
      end
    end
  end

  setup tags do
    if Map.get(tags, :use_bypass) === false do
      :ok
    else
      bird =
        case Map.get(tags, :bird) do
          bird when bird in @mocked_birds -> bird
          nil -> nil
        end

      images_module = Map.get(tags, :images_service, Flickr)
      recordings_module = Map.get(tags, :recordings_module, XenoCanto)
      observations_module = Map.get(tags, :observations_service, Ebird)

      [{:ok, recordings_server}, {:ok, images_server}, {:ok, observations_server}] =
        Enum.map(
          [
            recordings_module,
            images_module,
            observations_module
          ],
          &start_service_supervised(&1, tags)
        )

      services = %Services{
        bird: bird,
        images: %Service{name: images_module, whereis: images_server},
        recordings: %Service{name: recordings_module, whereis: recordings_server},
        observations: %Service{name: observations_module, whereis: observations_server},
        timeout: Map.get(tags, :timeout, 1_000)
      }

      {:ok, bypass} = setup_bypass(services)

      setup_mocks(tags, bypass)

      {:ok, bypass: bypass, services: services}
    end
  end

  def start_service_supervised(module, %{test: test}) do
    module_alias =
      module
      |> Module.split()
      |> List.last()

    test
    |> Module.concat(module_alias)
    |> TestHelpers.start_cache(module)
  end

  defguard is_configured_service(service_name) when service_name in [XenoCanto, Flickr, Ebird]
  defguard is_module_name(name) when is_atom(name) and name not in [:xeno_canto, :flickr, :ebird]

  def setup_bypass(%Services{} = services) do
    bypass = Bypass.open()
    do_for_services(services, &update_base_url(&1, bypass))
    {:ok, bypass}
  end

  @type bypass_generic_cb :: (Plug.Conn.t() -> Plug.Conn.t())
  @type bypass_path_cb :: {String.t(), String.t(), bypass_generic_cb()}

  @spec setup_mocks(
          %{
            optional(:expect_once) => bypass_generic_cb() | List.t(bypass_generic_cb()),
            optional(:expect) => bypass_generic_cb() | List.t(bypass_generic_cb()),
            optional(:stub) => bypass_path_cb() | List.t(bypass_path_cb()),
            optional(any) => any
          },
          Bypass.t()
        ) :: :ok
  def setup_mocks(%{expect_once: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect_once(bypass, func)

  def setup_mocks(
        %{expect_once: [{"" <> _, "" <> _, func} | _] = funcs},
        %Bypass{} = bypass
      )
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect_once(bypass, method, path, func)
        end)

  def setup_mocks(%{expect: func}, %Bypass{} = bypass) when is_function(func),
    do: Bypass.expect(bypass, func)

  def setup_mocks(
        %{expect: [{"" <> _, "" <> _, func} | _] = funcs},
        %Bypass{} = bypass
      )
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} -> Bypass.expect(bypass, method, path, func) end)

  def setup_mocks(%{stub: {"" <> method, "" <> path, func}}, %Bypass{} = bypass)
      when is_function(func),
      do: Bypass.stub(bypass, method, path, func)

  def setup_mocks(%{stub: [{"" <> _, "" <> _, func} | _] = funcs}, %Bypass{} = bypass)
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.stub(bypass, method, path, func)
        end)

  def setup_mocks(%{use_mock: false}, %Bypass{}), do: :ok

  def update_base_url(%Service{name: name}, %Bypass{} = bypass) do
    update_base_url(name, bypass)
  end

  def update_base_url(%Service{name: name}, "" <> url) do
    update_base_url(name, url)
  end

  def update_base_url(service_name, %Bypass{} = bypass)
      when is_configured_service(service_name) do
    do_update_base_url(service_name, mock_url(bypass))
  end

  def update_base_url(service_name, "" <> url) when is_configured_service(service_name) do
    do_update_base_url(service_name, url)
  end

  def update_base_url(service_name, %Bypass{}) when is_module_name(service_name) do
    :not_updated
  end

  def update_base_url(service_name, "" <> _) when is_module_name(service_name) do
    :not_updated
  end

  defp do_update_base_url(service_name, url) do
    TestHelpers.update_env(service_name, :base_url, url)
    {:ok, {service_name, url}}
  end

  def mock_url(%Bypass{port: port}), do: "http://localhost:#{port}"

  def do_for_services(%Services{} = services, callback) when is_function(callback) do
    for %Service{} = service <- services |> Map.from_struct() |> Map.values() do
      callback.(service)
    end
  end
end
