defmodule BirdSong.Services.Supervisor do
  @moduledoc """
  Supervisor for a service and all its children. Also starts a RequestThrottler
  for all services.

  To provide custom options to a child worker during tests, send it in the supervisor's
  init options as `[{:ChildName, [option1: :foo]} | supervisor_opts]`.
  """
  alias BirdSong.{
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

  defmacro __using__(opts) do
    quote do
      use BirdSong.Services.Supervisor.Using, unquote(opts)
    end
  end

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

  def instance_name(opts, module) when is_list(opts) do
    opts
    |> Keyword.fetch!(:service_name)
    |> instance_name(module)
  end

  def instance_name(name, _module) when is_atom(name) do
    Module.concat(name, :Supervisor)
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
