defmodule BirdSong.Services.Supervisor do
  @moduledoc """
  Supervisor for a service and all its children. Starts a RequestThrottler for all services,
  and any additional children indicated in the `:other_children` option passed to
  `use BirdSong.Services.Supervisor`.

  To provide custom options to a child worker during tests, send it in the supervisor's
  init options as `[{:ChildName, [option1: :foo]} | supervisor_opts]`.
  """
  alias BirdSong.{
    Services,
    Services.Service,
    Services.Worker
  }

  alias __MODULE__.{NotStartedError, ForbiddenExternalURLError}

  @typedoc """
  The atomized name of an ExUnit test, i.e. `:"test lorem ipsum dolor sit amet"`
  """
  @type test_name() :: atom()

  @typedoc """
  The name of the actual module where `use BirdSong.Services.Supervisor` is called.
  This will always be the same for all instances of the service.
  """
  @type service_module() :: module()

  @typedoc """
  The name of an instance of a service, started as part of a supervision tree.
  This will be the service name in `:prod` and `:dev`, but tests can start a service
  using the test name as the service name to ensure that test values are isolated.
  """
  @type service_instance_name(service_modul) :: service_modul | test_name()
  @type service_instance_name() :: service_instance_name(service_module())

  @typedoc """
  The module name of a service's child, where the child's methods are defined.
  """
  @type instance_worker_module() :: module()
  @type instance_worker_module(service_modul, worker_atom) ::
          Module.concat(service_modul, worker_atom)

  @typedoc """
  The unique single-atom version of a service's child worker module.

  For example:
  `instance_worker_module()` ->
    `BirdSong.Services.RequestThrottler`
  `instance_worker_atom()` ->
    `:RequestThrottler`
  `instance_worker_name()` ->
    `BirdSong.Services.Ebird.RequestThrottler` (or `:"test blah blah".RequestThrottler` in tests)
  """
  @type instance_worker_atom() :: atom()

  # The name of a child worker of a supervisor.

  # This name is built by concatenating the last part of the child module's name
  # with the supervisor instance name. For example, the instance named Ebird has a
  # `RequestThrottler` instance named `Ebird.RequestThrottler`, while the module that defines
  # the request throttler is always `BirdSong.Services.RequestThrottler`.
  # Calling `GenServer.whereis/1` on an instance worker name will return a PID.
  @type instance_worker_name(name_atom) :: Module.concat(service_instance_name(), name_atom)
  @type instance_worker_name() :: instance_worker_name(instance_worker_atom())

  @type service_struct(service_mod, worker_atom) :: %{
          required(:__struct__) => service_mod,
          required(worker_atom) => Worker.t()
        }

  @type service_struct() ::
          service_struct(service_module(), instance_worker_atom())

  @typedoc """
  The name of the actual supervisor instance that is supervising all of the service's workers.
  """
  @type supervisor_instance_name() :: instance_worker_name(:Supervisor)

  @type default_supervisor_option() :: {:service_name, service_instance_name(module())}
  @type default_supervisor_options() :: [default_supervisor_option()]

  @type supervisor_options() :: [default_supervisor_option() | {atom(), any()}]

  @type service_name_or_options(option) :: service_instance_name() | [option]

  #########################################################
  #########################################################
  ##
  ##  BEHAVIOUR SPECS
  ##
  #########################################################
  @callback services() :: service_struct()

  @callback services(service_instance_name()) :: service_struct()

  @callback default_service_name() :: service_module()

  @callback child_name(
              service_name_or_options(Keyword.t()),
              instance_worker_atom()
            ) :: instance_worker_name()

  @callback child_module(instance_worker_atom()) :: instance_worker_module()

  @callback get_instance_child(
              service_instance_name(),
              instance_worker_atom()
            ) :: Worker.t()

  def build_worker_info(service_module, child_atom) do
    build_worker_info(service_module, child_atom, service_module)
  end

  def build_worker_info(service_module, child_atom, service_instance) do
    instance_name = Module.concat(service_instance, child_atom)

    struct(Worker,
      instance_name: instance_name,
      module: Module.concat(service_module, child_atom),
      atom: child_atom,
      parent: struct(Service, name: service_instance, module: service_module)
    )
  end

  defmacro __using__(use_opts) do
    use_opts = Map.new(use_opts)

    caches =
      case use_opts do
        %{caches: [_ | _] = caches} ->
          caches

        _ ->
          raise ArgumentError.exception(
                  message:
                    "" <>
                      "use BirdSong.Services.Supervisor expects to receive a :caches option, " <>
                      "which should be a list of the names of its ThrottledCache children " <>
                      "as atoms, i.e. [caches: [:Observations, :Regions]]"
                )
      end

    other_children =
      case use_opts do
        %{other_children: [_ | _] = children} -> children
        %{} -> []
      end

    base_url =
      case use_opts do
        %{base_url: "" <> base_url} ->
          base_url

        _ ->
          raise ArgumentError.exception(
                  message:
                    "" <>
                      "use BirdSong.Services.Supervisor expects to receive a :base_url option, " <>
                      "which should be the full external URL as a string."
                )
      end

    custom_options =
      case use_opts do
        %{custom_options: [_ | _] = custom, use_data_folder?: true} ->
          [:data_folder_path | custom]

        %{custom_options: [_ | _] = custom} ->
          custom

        %{use_data_folder?: true} ->
          [:data_folder_path]

        _ ->
          []
      end

    struct = [:name | caches]

    quote bind_quoted: [
            base_url: base_url,
            caches: caches,
            custom_options: custom_options,
            other_children: other_children,
            struct: struct
          ] do
      use Elixir.Supervisor

      require BirdSong.Services.Supervisor

      import BirdSong.Services.Supervisor,
        except: [
          build_worker_info: 2,
          build_worker_info: 3
        ]

      @behaviour BirdSong.Services.Supervisor

      alias BirdSong.Services.Supervisor, as: Sup

      alias BirdSong.{
        Services,
        Services.Service,
        Services.RequestThrottler
      }

      @overridable [child_module: 1, do_opts_for_child: 2]

      #########################################################
      #########################################################
      ##
      ##  TYPESPECS
      ##
      #########################################################

      @type this_instance_name() ::
              BirdSong.Services.Supervisor.service_instance_name(__MODULE__)
      @type option() ::
              {:base_url, String.t()}
              | {:service_name, this_instance_name()}
              | {:allow_external_calls?, boolean}
              | {:throttle_ms, integer()}

      #########################################################
      #########################################################
      ##
      ##  ATTRIBUTES
      ##
      #########################################################

      @base_url base_url

      @caches caches

      @other_children other_children

      @child_names List.flatten([:RequestThrottler, @other_children, @caches])

      @default_opts [
        base_url: base_url,
        service_name: __MODULE__
      ]

      @opt_keys [
                  :base_url,
                  :allow_external_calls?,
                  :service_name,
                  :throttle_ms
                ] ++ @child_names ++ custom_options

      @opt_keys_set MapSet.new(@opt_keys)

      @enforce_keys Enum.map(struct, fn
                      {key, _} -> key
                      key -> key
                    end)
      defstruct struct

      #########################################################
      #########################################################
      ##
      ##  GUARDS
      ##
      #########################################################
      defguard is_child_name(name) when name in @child_names

      #########################################################
      #########################################################
      ##
      ##  PUBLIC API
      ##
      #########################################################

      @spec base_url() :: String.t()
      def base_url(), do: @base_url

      @spec base_url(this_instance_name()) :: String.t()
      def base_url(instance_name) do
        when_service_instance_name instance_name, __MODULE__ do
          instance_name
          |> child_name(:RequestThrottler)
          |> GenServer.call(:base_url)
        end
      end

      # @impl Sup
      @spec child_name(Sup.service_name_or_options(option()), Sup.instance_worker_atom()) ::
              Sup.instance_worker_name()
      def child_name(opts, child)
          when is_list(opts) and is_child_name(child) do
        opts
        |> Keyword.fetch!(:service_name)
        |> child_name(child)
      end

      def child_name(service, child) when is_child_name(child) do
        when_service_instance_name service, __MODULE__ do
          concat_name(service, child)
        end
      end

      # @impl Sup
      @spec child_module(Sup.instance_worker_atom()) :: Sup.instance_worker_module()
      def child_module(child) when is_child_name(child), do: concat_name(__MODULE__, child)

      # @impl Sup
      @spec default_service_name() :: module()
      def default_service_name() do
        Keyword.fetch!(@default_opts, :service_name)
      end

      defdelegate fetch(map, key), to: Map

      # @impl Sup
      @spec get_instance_child(this_instance_name(), module()) :: Worker.t()
      def get_instance_child(service_instance \\ __MODULE__, child) do
        when_service_instance_name service_instance, __MODULE__ do
          service_instance
          |> map_of_child_pids()
          |> get_instance_child(service_instance, child)
        end
      end

      # @impl Sup
      def services() do
        default_service_name()
        |> services()
      end

      # @impl Sup
      def services(instance_name) do
        when_service_instance_name instance_name, __MODULE__ do
          @caches
          |> Enum.map(
            &{&1,
             instance_name
             |> map_of_child_pids()
             |> get_instance_child(instance_name, &1)}
          )
          |> Keyword.new()
          |> Keyword.put(:name, instance_name)
          |> __struct__()
        end
      end

      def whereis_supervisor!(service_instance_name) do
        Sup.whereis!(service_instance_name, __MODULE__)
      end

      defp map_of_child_pids(service) do
        service
        |> whereis_supervisor!()
        |> Elixir.Supervisor.which_children()
        |> Enum.reduce(%{}, &add_child_pid_to_map/2)
      end

      #########################################################
      #########################################################
      ##
      ##  SUPERVISOR CALLBACKS
      ##
      #########################################################

      def start_link(opts) do
        opts
        |> raise_unused_opts()
        |> with_default_opts()
        |> Sup.start_link(__MODULE__)
      end

      @impl Supervisor
      def init(opts) do
        opts
        |> child_specs()
        |> Elixir.Supervisor.init(strategy: :one_for_one)
      end

      #########################################################
      #########################################################
      ##
      ##  PRIVATE METHODS
      ##
      #########################################################

      @typep which_children_item() ::
               {
                 Sup.instance_worker_module(),
                 pid(),
                 :worker,
                 [Sup.instance_worker_module()]
               }
      @typep child_pid_map() :: %{
               Sup.instance_worker_module() => pid()
             }

      @spec add_child_pid_to_map(which_children_item(), child_pid_map()) :: child_pid_map()
      defp add_child_pid_to_map({module, pid, :worker, [module]}, acc) do
        Map.put(acc, module, pid)
      end

      defp add_worker_to_child_opts(child_opts, parent_opts, child_name) do
        Keyword.put(child_opts, :worker, build_worker_info(parent_opts, child_name))
      end

      @spec child_specs(Sup.supervisor_options()) :: [Supervisor.child_spec()]
      defp child_specs(opts) when is_list(opts) do
        opts
        |> with_default_opts()
        |> raise_unused_opts()
        |> Sup.parse_base_url()
        |> do_child_specs()
      end

      # make public function available only for tests
      if Mix.env() === :test do
        def child_specs___test(opts) do
          child_specs(opts)
        end
      end

      @spec do_child_specs(Sup.supervisor_options()) :: [Supervisor.child_spec()]
      defp do_child_specs(opts) do
        Enum.map(
          @child_names,
          &{
            child_module(&1),
            opts_for_child(opts, &1)
          }
        )
      end

      defp concat_name(parent, child) when is_atom(parent) and is_atom(child) do
        Module.concat(parent, child)
      end

      defp get_instance_child(%{} = supervisor_children, service_instance, child)
           when is_child_name(child) do
        expected_pid = Map.fetch!(supervisor_children, child_module(child))
        worker = build_worker_info(service_instance, child)
        worker_pid = GenServer.whereis(worker.instance_name)

        if worker_pid !== expected_pid do
          raise RuntimeError.exception(
                  message: """
                  PID of worker instance name does not match supervisor child PID!


                  expected: #{inspect(expected_pid)}
                  got: #{inspect(worker_pid)}
                  worker: #{inspect(worker)}
                  supervisor_children: #{inspect(supervisor_children)}
                  """
                )
        end

        worker
      end

      defp build_service_info(service_instance) do
        struct(Service,
          name: service_instance,
          module: __MODULE__
        )
      end

      defp build_worker_info(opts, child_atom) when is_list(opts) do
        opts
        |> Keyword.fetch!(:service_name)
        |> build_worker_info(child_atom)
      end

      defp build_worker_info(service_instance, child_atom)
           when is_child_name(child_atom) do
        instance_name = child_name(service_instance, child_atom)

        struct(Worker,
          atom: child_atom,
          instance_name: instance_name,
          module: child_module(child_atom),
          name: child_atom,
          parent: build_service_info(service_instance)
        )
      end

      defp opts_for_child(opts, child) when is_child_name(child) do
        child_keys =
          child
          |> child_module()
          |> apply(:start_link_option_keys, [])

        opts
        |> Keyword.merge(Keyword.get(opts, child, []))
        |> add_worker_to_child_opts(opts, child)
        |> do_opts_for_child(child)
        |> Keyword.take([:worker | child_keys])
      end

      defp do_opts_for_child(opts, child) when is_child_name(child) do
        opts
      end

      defp raise_unused_opts(opts) do
        opts
        |> Keyword.keys()
        |> MapSet.new()
        |> MapSet.difference(@opt_keys_set)
        |> MapSet.to_list()
        |> case do
          [] ->
            opts

          [_ | _] = keys ->
            raise Sup.UnknownOptionKeyError.exception(keys: keys, module: __MODULE__)
        end
      end

      defp with_default_opts(opts) do
        @default_opts
        |> Keyword.merge(opts)
      end

      defoverridable(@overridable)
    end
  end

  defmacro when_service_instance_name(given, expected, do: a_s_t) do
    quote do
      given = unquote(given)
      expected = unquote(expected)

      cond do
        given === expected or
            given
            |> Atom.to_string()
            |> String.contains?("test ") ->
          unquote(a_s_t)

        true ->
          raise ArgumentError.exception(
                  message: """

                  Expected service_name to be either #{inspect(unquote(expected))} or a test name, but got:

                  #{inspect(unquote(given))}

                  """
                )
      end
    end
  end

  def instance_name(opts, module) when is_list(opts) do
    opts
    |> Keyword.fetch!(:service_name)
    |> instance_name(module)
  end

  def instance_name(name, module) when is_atom(name) do
    when_service_instance_name name, module do
      Module.concat(name, :Supervisor)
    end
  end

  def start_link(opts, module) do
    Elixir.Supervisor.start_link(
      module,
      opts,
      name: instance_name(opts, module)
    )
  end

  @spec parse_base_url([{:base_url, String.t()} | {atom(), any()}]) :: [
          {:base_url, URI.t() | ForbiddenExternalURLError.t()}
        ]
  def parse_base_url(opts) do
    Keyword.update!(opts, :base_url, &(opts |> Map.new() |> uri_or_error(Mix.env(), &1)))
  end

  def whereis!(%Service{name: instance_name, module: module}) do
    whereis!(instance_name, module)
  end

  def whereis!(service_instance_name, module) do
    supervisor = instance_name(service_instance_name, module)

    supervisor
    |> GenServer.whereis()
    |> case do
      nil ->
        raise NotStartedError.exception(
                module: module,
                service: service_instance_name,
                supervisor: supervisor
              )

      pid when is_pid(pid) ->
        pid
    end
  end

  @spec uri_or_error(
          %{
            required(:base_url) => String.t(),
            optional(:allow_external_calls?) => boolean()
          },
          :dev | :test | :prod,
          String.t()
        ) :: URI.t() | ForbiddenExternalURLError.t()
  defp uri_or_error(%{}, _env, {:error, error}) do
    {:error, error}
  end

  defp uri_or_error(%{} = opts, env, %URI{} = uri) do
    uri_or_error(opts, env, URI.to_string(uri))
  end

  # use whatever is provided in dev and prod
  defp uri_or_error(%{}, env, "http" <> _ = base_url) when env in [:dev, :prod] do
    URI.new!(base_url)
  end

  # localhost URLs are always allowed in test
  defp uri_or_error(%{}, :test, "http://localhost" <> _ = localhost) do
    URI.new!(localhost)
  end

  # anything else can only be used if explictly indicated
  defp uri_or_error(
         %{allow_external_calls?: true},
         :test,
         "https://" <> _ = external_url
       ) do
    URI.new!(external_url)
  end

  defp uri_or_error(%{} = opts, :test, "http" <> _) do
    {:error, ForbiddenExternalURLError.exception(opts: Keyword.new(opts))}
  end
end
