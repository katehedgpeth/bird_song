defmodule BirdSong.Services.Supervisor.Using do
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

    struct = [:name | caches]

    quote bind_quoted: [
            base_url: base_url,
            caches: caches,
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

      alias BirdSong.{
        Services,
        Services.Service,
        Services.RequestThrottler,
        Services.Worker
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

      @child_names List.flatten([:RequestThrottler, @caches])

      @default_opts [
        base_url: base_url,
        service_name: __MODULE__
      ]

      @opt_keys [
                  :base_url,
                  :allow_external_calls?,
                  :service_name,
                  :throttle_ms
                ] ++ @child_names

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
        instance_name
        |> child_name(:RequestThrottler)
        |> GenServer.call(:base_url)
      end

      # @impl Sup
      @spec child_name(
              Services.Supervisor.service_name_or_options(option()),
              Services.Supervisor.instance_worker_atom()
            ) ::
              Services.Supervisor.instance_worker_name()
      def child_name(opts, child)
          when is_list(opts) and is_child_name(child) do
        opts
        |> Keyword.fetch!(:service_name)
        |> child_name(child)
      end

      def child_name(service, child) when is_child_name(child) do
        concat_name(service, child)
      end

      # @impl Sup
      @spec child_module(Services.Supervisor.instance_worker_atom()) ::
              Services.Supervisor.instance_worker_module()
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
        service_instance
        |> map_of_child_pids()
        |> get_instance_child(service_instance, child)
      end

      # @impl Sup
      def services() do
        default_service_name()
        |> services()
      end

      # @impl Sup
      def services(instance_name) do
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

      def whereis_supervisor!(service_instance_name) do
        Services.Supervisor.whereis!(service_instance_name, __MODULE__)
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
        |> Services.Supervisor.start_link(__MODULE__)
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
                 Services.Supervisor.instance_worker_module(),
                 pid(),
                 :worker,
                 [Services.Supervisor.instance_worker_module()]
               }
      @typep child_pid_map() :: %{
               Services.Supervisor.instance_worker_module() => pid()
             }

      @spec add_child_pid_to_map(which_children_item(), child_pid_map()) :: child_pid_map()
      defp add_child_pid_to_map({module, pid, :worker, [module]}, acc) do
        Map.put(acc, module, pid)
      end

      defp add_worker_to_child_opts(child_opts, parent_opts, child_name) do
        Keyword.put(child_opts, :worker, build_worker_info(parent_opts, child_name))
      end

      @spec child_specs(Services.Supervisor.supervisor_options()) :: [Supervisor.child_spec()]
      defp child_specs(opts) when is_list(opts) do
        opts
        |> with_default_opts()
        |> raise_unused_opts()
        |> Services.Supervisor.parse_base_url()
        |> do_child_specs()
      end

      # make public function available only for tests
      if Mix.env() === :test do
        def child_specs___test(opts) do
          child_specs(opts)
        end
      end

      @spec do_child_specs(Services.Supervisor.supervisor_options()) :: [Supervisor.child_spec()]
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
            raise Services.Supervisor.UnknownOptionKeyError.exception(
                    keys: keys,
                    module: __MODULE__
                  )
        end
      end

      defp with_default_opts(opts) do
        @default_opts
        |> Keyword.merge(opts)
      end

      defoverridable(@overridable)
    end
  end
end
