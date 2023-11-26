defmodule BirdSong.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @children List.flatten([
              # Start the Ecto repository
              BirdSong.Repo,
              [
                BirdSong.Services,
                # Start the Telemetry supervisor
                BirdSongWeb.Telemetry,
                # Start the PubSub system
                {Phoenix.PubSub, name: BirdSong.PubSub},
                # Start the Endpoint (http/https)
                {SiteEncrypt.Phoenix, BirdSongWeb.Endpoint}
                # Start a worker by calling: BirdSong.Worker.start_link(arg)
                # {BirdSong.Worker, arg}
              ]
            ])

  @impl true
  def start(_type, _args) do
    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BirdSong.Supervisor]
    Supervisor.start_link(@children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BirdSongWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  def log_named_servers() do
    groups =
      @children
      |> Enum.map(&log_named_server/1)
      |> Enum.group_by(&elem(&1, 1))
      |> Enum.map(fn {key, val} -> {key, Enum.into(val, %{})} end)

    IO.inspect(
      named_servers: groups |> Keyword.fetch!(true) |> Map.keys(),
      unnamed_servers: groups |> Keyword.get(false, %{}) |> Map.keys()
    )
  end

  defp log_named_server(%{start: {module, :start_link, [opts]}}) when is_list(opts) do
    log_named_server({module, opts})
  end

  defp log_named_server({module, opts}) when is_atom(module) and is_list(opts) do
    case Keyword.get(opts, :name) do
      nil -> log_named_server(module)
      name -> log_named_server(name)
    end
  end

  defp log_named_server(server) when is_atom(server) do
    {server,
     server
     |> GenServer.whereis()
     |> is_pid()}
  end
end
