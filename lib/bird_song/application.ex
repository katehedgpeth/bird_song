defmodule BirdSong.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Ecto repository
      BirdSong.Repo,
      # Start the Telemetry supervisor
      BirdSongWeb.Telemetry,
      # Start the supervisors for external API requests
      {Task.Supervisor, name: BirdSong.Services.Tasks},
      {DynamicSupervisor, name: BirdSong.Services.GenServers},
      # Start service caches
      BirdSong.Services.XenoCanto,
      BirdSong.Services.Flickr,
      # Start the PubSub system
      {Phoenix.PubSub, name: BirdSong.PubSub},
      # Start the Endpoint (http/https)
      BirdSongWeb.Endpoint
      # Start a worker by calling: BirdSong.Worker.start_link(arg)
      # {BirdSong.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BirdSong.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BirdSongWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
