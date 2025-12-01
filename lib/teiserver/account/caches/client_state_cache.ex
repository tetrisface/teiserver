defmodule Teiserver.Account.Caches.ClientStateCache do
  @moduledoc """
  Fast ETS-backed read cache for client state.
  This avoids GenServer.call overhead for frequent client lookups.

  The cache is kept in sync by ClientServer whenever client state changes.
  Updates are broadcast via PubSub to keep all nodes in sync.
  """
  use GenServer
  require Logger
  alias Phoenix.PubSub

  @table_name :teiserver_client_state_cache
  @cluster_channel "client_state_cache_sync"

  # Public API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec get(integer()) :: nil | map()
  def get(userid) when is_integer(userid) do
    case :ets.lookup(@table_name, userid) do
      [{^userid, client}] -> client
      [] -> nil
    end
  end

  def get(_), do: nil

  @spec put(integer(), map()) :: :ok
  def put(userid, client) when is_integer(userid) do
    # Update local ETS
    :ets.insert(@table_name, {userid, client})

    # Broadcast to cluster (other nodes will update their ETS)
    PubSub.broadcast(
      Teiserver.PubSub,
      @cluster_channel,
      {:client_state_cache, :put, Node.self(), userid, client}
    )

    :ok
  end

  def put(_, _), do: :ok

  @spec delete(integer()) :: :ok
  def delete(userid) when is_integer(userid) do
    # Delete from local ETS
    :ets.delete(@table_name, userid)

    # Broadcast to cluster
    PubSub.broadcast(
      Teiserver.PubSub,
      @cluster_channel,
      {:client_state_cache, :delete, Node.self(), userid}
    )

    :ok
  end

  def delete(_), do: :ok

  # GenServer callbacks
  @impl true
  def init(_) do
    # Create a public ETS table for fast concurrent reads
    # :set type for unique keys, :public for concurrent access
    :ets.new(@table_name, [:set, :public, :named_table, read_concurrency: true])

    # Subscribe to cluster sync messages
    :ok = PubSub.subscribe(Teiserver.PubSub, @cluster_channel)

    {:ok, %{}}
  end

  @impl true
  def handle_info({:client_state_cache, :put, from_node, userid, client}, state) do
    # Only update if message is from another node (avoid duplicate local updates)
    if from_node != Node.self() do
      :ets.insert(@table_name, {userid, client})
    end

    {:noreply, state}
  end

  def handle_info({:client_state_cache, :delete, from_node, userid}, state) do
    # Only delete if message is from another node
    if from_node != Node.self() do
      :ets.delete(@table_name, userid)
    end

    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}
end
