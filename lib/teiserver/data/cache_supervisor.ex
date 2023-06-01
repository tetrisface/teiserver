defmodule Teiserver.Data.CacheSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      concache_sup(:codes),
      concache_sup(:account_user_cache),
      concache_sup(:account_user_cache_bang),
      concache_sup(:account_membership_cache),



        # Store refers to something that is typically only updated at startup
        # and should not be clustered
        concache_perm_sup(:recently_used_cache),
        concache_perm_sup(:auth_group_store),
        concache_perm_sup(:group_type_store),
        concache_perm_sup(:restriction_lookup_store),
        concache_perm_sup(:config_user_type_store),
        concache_perm_sup(:config_site_type_store),
        concache_perm_sup(:config_site_cache),
        concache_perm_sup(:application_metadata_cache),

        concache_sup(:application_temp_cache),
        concache_sup(:config_user_cache),
        concache_sup(:communication_user_notifications),

        # Tachyon schemas
        concache_perm_sup(:tachyon_schemas),
        concache_perm_sup(:tachyon_dispatches),


        # Stores - Tables where changes are not propagated across the cluster
        # Possible stores
        concache_perm_sup(:teiserver_queues),
        concache_perm_sup(:lobby_policies_cache),

        # Telemetry
        concache_perm_sup(:teiserver_telemetry_event_types),
        concache_perm_sup(:teiserver_telemetry_property_types),
        concache_perm_sup(:teiserver_telemetry_game_event_types),
        concache_perm_sup(:teiserver_account_smurf_key_types),
        concache_sup(:teiserver_user_ratings, global_ttl: 60_000),
        concache_sup(:teiserver_game_rating_types, global_ttl: 60_000),

        # Caches
        # Caches - Meta
        concache_perm_sup(:lists),

        # Caches - User
        # concache_sup(:users_lookup_name_with_id, [global_ttl: 300_000]),
        # concache_sup(:users_lookup_id_with_name, [global_ttl: 300_000]),
        # concache_sup(:users_lookup_id_with_email, [global_ttl: 300_000]),
        # concache_sup(:users_lookup_id_with_discord, [global_ttl: 300_000]),
        # concache_sup(:users, [global_ttl: 300_000]),

        concache_perm_sup(:users_lookup_name_with_id),
        concache_perm_sup(:users_lookup_id_with_name),
        concache_perm_sup(:users_lookup_id_with_email),
        concache_perm_sup(:users_lookup_id_with_discord),
        concache_perm_sup(:users),
        concache_sup(:teiserver_login_count, global_ttl: 10_000),
        concache_sup(:teiserver_user_stat_cache),

        # Caches - Battle/Queue/Clan
        concache_sup(:teiserver_clan_cache_bang),

        # Caches - Chat
        concache_perm_sup(:rooms),

        concache_sup(:discord_bridge_dm_cache),
        concache_sup(:discord_bridge_account_codes, global_ttl: 300_000),

        # Text callbacks
        concache_perm_sup(:text_callback_trigger_lookup),
        concache_perm_sup(:text_callback_store),


    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp concache_sup(name, _opts \\ []) do
    Supervisor.child_spec(
      {
        Cachex,
        [
          name: name,
          # ttl_check_interval: 10_000,
          # global_ttl: opts[:global_ttl] || 60_000,
          # touch_on_read: true
        ]
      },
      id: {Cachex, name}
    )
  end

  defp concache_perm_sup(name) do
    Supervisor.child_spec(
      {
        Cachex,
        [
          name: name,
          # ttl_check_interval: 10_000,
          # global_ttl: opts[:global_ttl] || 60_000,
          # touch_on_read: true
        ]
      },
      id: {Cachex, name}
    )
  end
end
