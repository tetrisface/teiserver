1. Client state lookup performance bottleneck
Location: lib/teiserver/account/libs/client_lib.ex:27-29
def get_client_by_id(userid) do  call_client(userid, :get_client_state)  # GenServer.call for EVERY lookup!end
Problem: Every client lookup does a synchronous GenServer.call. With many lookups (156+ usages), this adds latency and can block.
Impact: High-frequency operations (lobby updates, chat, battle status) become slow.
2. Client lifecycle and cache inconsistency
Location: lib/teiserver/account/servers/client_server.ex:205-218
The heartbeat mechanism checks if the TCP process is alive, but:
Client state lives in the GenServer process
Related caches (account_user_cache, account_friend_cache, etc.) may not be cleaned up
On disconnect, the GenServer terminates, but cached data may remain
Problem: Stale cached data after disconnects, especially in clustered setups.
3. Cache proliferation and complexity
Location: lib/teiserver/application.ex:43-135
30+ ConCache instances:
account_user_cache, account_user_cache_bang
account_friend_cache, account_incoming_friend_request_cache, account_outgoing_friend_request_cache
account_follow_cache, account_ignore_cache, account_avoid_cache, account_block_cache
account_avoiding_this_cache, account_blocking_this_cache
Plus telemetry, config, lobby, room caches...
Problem: Hard to reason about, maintain, and debug. Cache invalidation is complex and error-prone.
4. Fragile cluster synchronization
Location: lib/teiserver/general/servers/cache_cluster_server.ex
The system tries to sync ETS across nodes via PubSub:
# Broadcasts cache updates to clusterPhoenix.PubSub.broadcast(Teiserver.PubSub, "cluster_hooks", ...)
Problems:
ETS is node-local; PubSub sync is a workaround
Race conditions possible
No guarantees about delivery or ordering
If a node is down during an update, it misses it
5. No graceful degradation
Location: lib/teiserver/helpers/cache_helper.ex:9-18
def cache_get(table, key), do: ConCache.get(table, key)def cache_get_or_store(table, key, func) do  ConCache.get_or_store(table, key, func)catch  :exit, :noproc ->    Logger.warning("Cache #{table} is down")    func.()  # Falls back, but only in get_or_storeend
Problem: Most cache operations have no fallback. If ConCache is down, the system fails instead of falling back to DB/GenServer.
6. Dual storage of client state
Client state exists in two places:
GenServer process state (ClientServer)
Potentially cached in various ConCache tables
Problem: Risk of inconsistency between process state and cached state, especially during updates.
7. Account relationship cache invalidation complexity
Location: lib/teiserver/account.ex:1741-1815
When relationships change, multiple caches must be invalidated:
Teiserver.cache_delete(:account_friend_cache, friend.user1_id)Teiserver.cache_delete(:account_friend_cache, friend.user2_id)
Problem: Easy to miss invalidations, leading to stale data. With many relationship types, this becomes error-prone.
Priority fixes
High: Replace get_client_by_id GenServer calls with a faster lookup (e.g., ETS-backed read-only cache or direct registry access)
High: Add a feature flag to disable ConCache and fall back to direct DB/GenServer lookups
Medium: Consolidate account relationship caches into a single cache
Medium: Improve cluster synchronization (consider Redis or a distributed GenServer)
Low: Add monitoring/alerting for cache misses and inconsistencies
Should I draft a solution for any of these?
