defmodule Observatory.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ObservatoryWeb.Telemetry,
      Observatory.Repo,
      {DNSCluster, query: Application.get_env(:observatory, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Observatory.PubSub},
      # Start a worker by calling: Observatory.Worker.start_link(arg)
      # {Observatory.Worker, arg},
      # Start to serve requests, typically the last entry
      ObservatoryWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Observatory.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ObservatoryWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
