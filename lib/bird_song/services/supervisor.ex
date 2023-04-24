defmodule BirdSong.Services.Supervisor do
  alias BirdSong.Services
  alias __MODULE__.NotStartedError

  Module.register_attribute(__MODULE__, :registered_tests, accumulate: true, persist: true)

  @type service_structs :: %{
          Services.Ebird => Services.Ebird.t()
        }
  @type test_name() :: :"test 'this is the name of a test'"
  @type service_atom() :: :Ebird
  @type service_name() :: Services.Ebird
  @type service_struct(service) :: service_structs[service]
  @type test_instance_name() :: Module.concat(test_name(), service_name())
  @type parent_name() :: service_name() | test_name()
  @type name(service) ::
          Module.concat(parent_name(), service, :Supervisor) | test_instance_name()

  @callback services(service_name()) :: service_struct(service_name())
  @callback default_service_name() :: service_name()

  defmacro __using__([]) do
    quote location: :keep do
      use Elixir.Supervisor

      alias BirdSong.Services.Supervisor, as: Sup
      require Sup
      @behaviour Sup
      import Sup, only: [when_service_instance_name: 3]

      def whereis_supervisor!(service_instance_name) do
        Sup.whereis!(service_instance_name, __MODULE__)
      end

      @spec map_of_child_pids(Sup.name()) :: map
      defp map_of_child_pids(service) do
        service
        |> whereis_supervisor!()
        |> Elixir.Supervisor.which_children()
        |> Enum.reduce(%{}, &add_child_pid_to_map/2)
      end

      defp add_child_pid_to_map({module, pid, :worker, [module]}, acc) do
        Map.put(acc, module, pid)
      end
    end
  end

  defmacro when_service_instance_name(given, expected, do: a_s_t) do
    quote do
      cond do
        unquote(given) === unquote(expected) ->
          unquote(a_s_t)

        match?("test " <> _, Atom.to_string(unquote(given))) ->
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
