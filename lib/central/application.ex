defmodule Central.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias Phoenix.PubSub
  require Logger

  @impl true
  def start(_type, _args) do
    # List all child processes to be supervised
    children =
      [
        # Start phoenix pubsub
        {Phoenix.PubSub, name: Central.PubSub},
        CentralWeb.Telemetry,

        # Start the Ecto repository
        Central.Repo,
        # Start the endpoint when the application starts
        CentralWeb.Endpoint,
        CentralWeb.Presence,
        Teiserver.Data.CacheSupervisor,
        {Central.General.CacheClusterServer, name: Central.General.CacheClusterServer},

        {Oban, oban_config()},


        # Teiserver stuff
        # Global/singleton registries
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.ServerRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.ThrottleRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.AccoladesRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.ConsulRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.BalancerRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.LobbyRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.ClientRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.PartyRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.QueueWaitRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.QueueMatchRegistry]},
        {Horde.Registry, [keys: :unique, members: :auto, name: Teiserver.LobbyPolicyRegistry]},

        # These are for tracking the number of servers on the local node
        {Registry, keys: :duplicate, name: Teiserver.LocalPoolRegistry},
        {Registry, keys: :duplicate, name: Teiserver.LocalServerRegistry},

        {Teiserver.HookServer, name: Teiserver.HookServer},

        # Liveview throttles
        Teiserver.Account.ClientIndexThrottle,
        Teiserver.Battle.LobbyIndexThrottle,
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.Throttles.Supervisor},

        # Bridge
        Teiserver.Bridge.BridgeServer,

        # Lobbies
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.LobbySupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.ClientSupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.PartySupervisor},
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.LobbyPolicySupervisor},

        # Matchmaking
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.Game.QueueSupervisor},

        # Coordinator mode
        {DynamicSupervisor,
         strategy: :one_for_one, name: Teiserver.Coordinator.DynamicSupervisor},
        {DynamicSupervisor,
         strategy: :one_for_one, name: Teiserver.Coordinator.BalancerDynamicSupervisor},

        # Accolades
        {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.Account.AccoladeSupervisor},

        # Achievements
        {Teiserver.Game.AchievementServer, name: Teiserver.Game.AchievementServer},

        # System throttle
        {Teiserver.Account.LoginThrottleServer, name: Teiserver.Account.LoginThrottleServer},

        # Telemetry
        {Teiserver.Telemetry.TelemetryServer, name: Teiserver.Telemetry.TelemetryServer},

        # Ranch servers
        %{
          id: Teiserver.SSLSpringTcpServer,
          start: {Teiserver.SpringTcpServer, :start_link, [[ssl: true]]}
        },
        %{
          id: Teiserver.RawSpringTcpServer,
          start: {Teiserver.SpringTcpServer, :start_link, [[]]}
        },
        %{
          id: Teiserver.TachyonTcpServer,
          start: {Teiserver.TachyonTcpServer, :start_link, [[]]}
        }
      ] ++ discord_start()

    # Agent mode stuff, should not be enabled in prod
    children =
      if Application.get_env(:central, Teiserver)[:enable_agent_mode] do
        children ++
          [
            {Registry, keys: :unique, name: Teiserver.Agents.ServerRegistry},
            {DynamicSupervisor, strategy: :one_for_one, name: Teiserver.Agents.DynamicSupervisor}
          ]
      else
        children
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Central.Supervisor]
    start_result = Supervisor.start_link(children, opts)

    # We use a logger.error to ensure something appears even on the error logs
    # and we can be sure they're being written to
    Logger.error("Central.Supervisor start result: #{Kernel.inspect(start_result)}")

    startup_sub_functions(start_result)

    start_result
  end

  defp discord_start do
    if Application.get_env(:central, Teiserver)[:enable_discord_bridge] do
      [{Teiserver.Bridge.DiscordBridge, name: Teiserver.Bridge.DiscordBridge}]
    else
      []
    end
  end

  def startup_sub_functions({:error, _}), do: :error

  def startup_sub_functions(_) do
    :timer.sleep(100)

    # Do migrations as part of startup
    path = Application.app_dir(:central, "priv/repo/migrations")
    Ecto.Migrator.run(Central.Repo, path, :up, all: true)

    # Oban logging
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception],
      [:oban, :circuit, :trip]
    ]

    :telemetry.attach_many("oban-logger", events, &Central.ObanLogger.handle_event/4, [])

    ~w(General Config Account Admin)
    |> Enum.each(&env_startup/1)

    Teiserver.Startup.startup()
  end

  defp env_startup(module) do
    mstartup = Module.concat(["Central", module, "Startup"])
    mstartup.startup()
  end

  defp oban_config do
    Application.get_env(:central, Oban)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CentralWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @impl true
  @spec prep_stop(map()) :: map()
  def prep_stop(state) do
    PubSub.broadcast(
      Central.PubSub,
      "application",
      %{
        channel: "application",
        event: :prep_stop,
        node: Node.self()
      }
    )

    state
  end
end
