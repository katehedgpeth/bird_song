defmodule BirdSong.Services.Supervisor do
  alias BirdSong.{
    Services,
    Services.Service
  }

  alias __MODULE__.NotStartedError

  # @type module() :: Atom.module_info(:module)

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

  @type instance_worker_info(instance, worker_atom) :: %Service{
          name: instance_worker_name(worker_atom),
          module: instance_worker_module(instance, worker_atom),
          whereis: pid()
        }

  @type instance_worker_info() ::
          instance_worker_info(service_instance_name(), instance_worker_atom())

  @type service_struct(instance, service_mod, worker_atom) :: %{
          required(:__struct__) => service_mod,
          required(worker_atom) => instance_worker_info(instance, worker_atom)
        }

  @type service_struct() ::
          service_struct(service_instance_name(), service_module(), instance_worker_atom())

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
            ) :: instance_worker_info()

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

    quote location: :keep,
          bind_quoted: [
            base_url: base_url,
            caches: caches,
            custom_options: custom_options,
            other_children: other_children
          ] do
      use Elixir.Supervisor

      require BirdSong.Services.Supervisor
      import BirdSong.Services.Supervisor
      @behaviour BirdSong.Services.Supervisor

      alias BirdSong.Services.Supervisor, as: Sup

      alias BirdSong.{
        Services,
        Services.Service,
        Services.RequestThrottler
      }

      #########################################################
      #########################################################
      ##
      ##  TYPESPECS
      ##
      #########################################################

      @type this_instance_name() :: BirdSong.Services.Supervisor.service_instance_name(__MODULE__)
      @type option() ::
              {:base_url, String.t()}
              | {:service_name, this_instance_name()}
              | {:allow_external_calls?, boolean}
              | {:throttle_ms, integer()}

      #########################################################
      #########################################################
      ##
      ##  GUARDS
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
        :throttle_ms | custom_options
      ]

      @opt_keys_set MapSet.new(@opt_keys)

      @enforce_keys @caches
      defstruct @caches

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
          %{RequestThrottler: %Service{whereis: whereis}} = map_of_child_pids(instance_name)

          GenServer.call(whereis, :base_url)
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
      def child_module(:RequestThrottler), do: RequestThrottler
      def child_module(child) when is_child_name(child), do: concat_name(__MODULE__, child)
      defoverridable(child_module: 1)

      # @impl Sup
      @spec default_service_name() :: module()
      def default_service_name() do
        Keyword.fetch!(@default_opts, :service_name)
      end

      # @impl Sup
      @spec get_instance_child(this_instance_name(), module()) ::
              Sup.instance_worker_info(this_instance_name(), Sup.instance_worker_atom())
      def get_instance_child(service_instance, child) do
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
      def services(service) do
        when_service_instance_name service, __MODULE__ do
          @caches
          |> Enum.map(
            &{&1,
             service
             |> map_of_child_pids()
             |> get_instance_child(service, &1)}
          )
          |> Keyword.new()
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
      defp(add_child_pid_to_map({module, pid, :worker, [module]}, acc)) do
        Map.put(acc, module, pid)
      end

      @spec child_specs(Sup.supervisor_options()) :: [Supervisor.child_spec()]
      defp child_specs(opts) when is_list(opts) do
        opts
        |> with_default_opts()
        |> raise_unused_opts()
        |> do_child_specs()
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

      defp concat_name(parent, child) when is_atom(parent) and is_child_name(child) do
        Module.concat(parent, child)
      end

      defp get_instance_child(%{} = supervisor_children, service_instance, child)
           when is_child_name(child) do
        supervisor_children
        |> Map.fetch!(child_module(child))
        |> do_get_instance_child(service_instance, child)
      end

      defp do_get_instance_child(child_pid, service_instance, child)
           when is_child_name(child) do
        %Service{
          whereis: child_pid,
          name: child_name(service_instance, child),
          module: child_module(child)
        }
      end

      defp opts_for_child(opts, child) when is_child_name(child) do
        opts
        |> Keyword.put(:name, child_name(opts, child))
        |> do_opts_for_child(child)
        |> Keyword.drop([:service_name])
      end

      defp do_opts_for_child(opts, :RegionETS) do
        Keyword.take(opts, [:name])
      end

      defp do_opts_for_child(opts, :RequestThrottler) do
        Keyword.drop(opts, [:data_folder_path, :throttler])
      end

      defp do_opts_for_child(opts, child) when child in @caches do
        opts
        |> Keyword.put(:throttler, child_name(opts, :RequestThrottler))
        |> Keyword.drop([:throttle_ms, :allow_external_calls?])
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
end
