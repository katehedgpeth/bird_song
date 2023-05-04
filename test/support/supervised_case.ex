defmodule BirdSong.SupervisedCase do
  @moduledoc """
  Starts the entire Services supervision tree.

  To disable using bypass for base urls:
    - `@tag use_bypass?: false`

  To add self to a service's listeners:
    - `@tag listen_to: [DataFile, Ebird, etc.]

  To add self to a worker's listeners:
    - `@tag listen_to: [{Ebird, :Regions}, {Flickr, :PhotoSearch}, etc.]`

  Helper functions:
    - start_services(tags) :: {:ok, options_given_to_services_supervisor}
    - get_service_name(service_module, tags) :: service_module()
    - get_worker(service_module, worker_atom, tags) :: Worker.t()
    - get_service_bypass(service_module, tags) :: [bypass: Bypass.t(), mock_url: String.t()]
  """
  use ExUnit.CaseTemplate

  alias BirdSong.{
    TestHelpers,
    Services
  }

  alias BirdSong.Services.{
    Ebird,
    Flickr,
    MacaulayLibrary,
    Worker,
    XenoCanto
  }

  @default_throttle_ms 100

  @services [Ebird, Flickr, MacaulayLibrary]

  @type bypass_info() :: [bypass: Bypass.t(), mock_url: String.t()]
  @type bypasses() :: %{
          required(Ebird) => bypass_info(),
          required(Flickr) => bypass_info(),
          required(MacaulayLibrary) => bypass_info(),
          required(XenoCanto) => bypass_info()
        }

  @type tags() :: %{
          required(:test) => atom(),
          required(:bypasses) => bypasses(),
          required(:base_urls) => Services.base_urls_map(),
          optional(:opts) => [Services.service_opts()],
          optional(atom()) => any()
        }

  using opts do
    services = Keyword.get(opts, :services, @services)

    use_db? = Keyword.get(opts, :use_db?, false)

    quote bind_quoted: [services: services, use_db?: use_db?] do
      if use_db? do
        use BirdSong.DataCase
      end

      alias BirdSong.{
        Services,
        Services.Service,
        Services.Worker,
        TestHelpers
      }

      import BirdSong.SupervisedCase,
        only: [
          get_service_bypass: 2,
          get_service_name: 2,
          get_worker: 3,
          get_worker_setup: 3,
          relative_tmp_dir: 1,
          start_services: 1,
          setup_service_bypass: 1
        ]

      @services services

      setup [:relative_tmp_dir, :setup_bypasses, :start_services]

      def setup_bypasses(%{use_bypass?: false}) do
        :ok
      end

      def setup_bypasses(%{}) do
        {:ok, bypasses: Map.new(@services, &setup_service_bypass/1)}
      end
    end
  end

  @spec start_services(%{
          required(:test) => atom(),
          optional(:bypasses) => bypasses(),
          optional(:start_services?) => boolean()
        }) ::
          {:ok,
           [
             {:name, atom()}
             | Services.base_urls_opt()
             | {:bypasses, bypasses()}
           ]}
  def start_services(%{start_services?: false}) do
    :ok
  end

  def start_services(%{test: test} = tags) do
    opts =
      tags
      |> Keyword.new()
      |> Keyword.get(:opts, [])
      |> Keyword.put_new(:throttle_ms, @default_throttle_ms)
      |> set_data_folder_path(tags)
      |> set_base_urls(tags)
      |> set_listeners(tags)
      |> Keyword.merge(name: test)

    start_link_supervised!({Services, opts})

    {:ok, opts}
  end

  @spec get_service_bypass(module, tags()) :: {:ok, bypass_info()} | :error
  def get_service_bypass(module, %{bypasses: bypasses}) do
    Map.fetch(bypasses, module)
  end

  def get_service_bypass(_module, %{}) do
    :error
  end

  @spec get_service_name(module(), Map.t()) :: module()
  def get_service_name(module, %{test: test}) do
    Services.service_instance_name(test, module)
  end

  @spec get_worker(module(), atom(), tags()) :: Worker.t()
  def get_worker(service_module, worker_atom, %{} = tags) do
    service_module
    |> get_service_name(tags)
    |> service_module.get_instance_child(worker_atom)
  end

  @spec get_worker_setup(module(), atom(), tags()) :: %{
          bypass: Bypass.t(),
          mock_url: String.t(),
          worker: Worker.t()
        }
  def get_worker_setup(service_module, worker_atom, %{} = tags) do
    service_module
    |> get_worker(worker_atom, tags)
    |> do_get_worker_setup(service_module, tags)
  end

  defp do_get_worker_setup(%Worker{} = worker, service_module, tags) do
    service_module
    |> get_service_bypass(tags)
    |> case do
      :error -> %{}
      {:ok, bypass} -> Map.new(bypass)
    end
    |> Map.merge(%{
      worker: worker
    })
  end

  def setup_mock_routes(%{use_mock_routes?: false}), do: :ok

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        expect_once: func
      })
      when is_function(func),
      do: Bypass.expect_once(bypass, func)

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        expect_once: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect_once(bypass, method, path, func)
        end)

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        expect: func
      })
      when is_function(func),
      do: Bypass.expect(bypass, func)

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        expect: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.expect(bypass, method, path, func)
        end)

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        stub: {"" <> method, "" <> path, func}
      })
      when is_function(func),
      do: Bypass.stub(bypass, method, path, func)

  def setup_mock_routes(%{
        bypass: %Bypass{} = bypass,
        stub: [{"" <> _, "" <> _, func} | _] = funcs
      })
      when is_function(func),
      do:
        Enum.each(funcs, fn {method, path, func} ->
          Bypass.stub(bypass, method, path, func)
        end)

  def add_self_to_service_listeners(service, opts) when is_atom(service) do
    opts
    |> Keyword.put_new(service, [])
    |> update_in([service, :listeners], &do_add_self_to_service_listeners/1)
  end

  def add_self_to_service_listeners({service, child}, opts) do
    opts
    |> Keyword.update(service, [{child, []}], &Keyword.put_new(&1, child, []))
    |> update_in([service, child, :listeners], &do_add_self_to_service_listeners/1)
  end

  defp do_add_self_to_service_listeners(nil) do
    [self()]
  end

  defp do_add_self_to_service_listeners(listeners) when is_list(listeners) do
    [self() | listeners]
  end

  defp set_data_folder_path(opts, %{tmp_dir: "" <> tmp_dir}) do
    Keyword.put(opts, :parent_data_folder, tmp_dir)
  end

  defp set_data_folder_path(opts, %{}) do
    opts
  end

  defp set_listeners(opts, %{listen_to: services}) do
    Enum.reduce(services, opts, &add_self_to_service_listeners/2)
  end

  defp set_listeners(opts, %{}) do
    opts
  end

  defp set_base_urls(opts, %{bypasses: bypasses}) do
    Keyword.put(
      opts,
      :base_urls,
      bypasses
      |> Enum.map(&{elem(&1, 0), elem(&1, 1)[:mock_url]})
      |> Keyword.new()
    )
  end

  defp set_base_urls(opts, %{}) do
    opts
  end

  def setup_service_bypass(module) do
    bypass = Bypass.open()
    {module, %{bypass: bypass, mock_url: TestHelpers.mock_url(bypass)}}
  end

  def relative_tmp_dir(%{tmp_dir: "" <> tmp_dir}) do
    {:ok, tmp_dir: Path.relative_to_cwd(tmp_dir)}
  end

  def relative_tmp_dir(%{}) do
    :ok
  end
end
