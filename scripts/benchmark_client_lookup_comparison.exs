#!/usr/bin/env elixir
# Comparison benchmark: Old way (GenServer.call) vs New way (ETS cache)
#
# Usage:
#   docker attach teiserver
#   Code.eval_file("scripts/benchmark_client_lookup_comparison.exs")

require Logger

defmodule ComparisonBenchmark do
  def run do
    Logger.info("=" <> String.duplicate("=", 60))
    Logger.info("Client Lookup Performance Comparison")
    Logger.info("Old (GenServer.call) vs New (ETS cache)")
    Logger.info("=" <> String.duplicate("=", 60))

    # Get some client IDs
    client_ids = Teiserver.Account.ClientLib.list_client_ids()

    if Enum.empty?(client_ids) do
      Logger.warning("""
      ⚠️  No clients connected.

      To test with real clients:
      1. Connect some clients to the server (via Chobby, Tachyon, etc.)
      2. Or create test clients programmatically

      Exiting...
      """)
      :ok
    else
      test_id = List.first(client_ids)
      Logger.info("📊 Benchmarking with client ID: #{test_id}")
      Logger.info("📈 Found #{length(client_ids)} total connected clients")
      Logger.info("")

      iterations = 10_000

      # Test 1: New way (ETS cache) - current implementation
      Logger.info("🔥 Warming up ETS cache...")
      Teiserver.Client.get_client_by_id(test_id)
      Process.sleep(100)

      Logger.info("⚡ Testing NEW way (ETS cache)...")
      {ets_time, _} =
        :timer.tc(fn ->
          Enum.each(1..iterations, fn _ ->
            Teiserver.Client.get_client_by_id(test_id)
          end)
        end)

      # Test 2: Old way (direct GenServer.call) - bypass cache
      Logger.info("⚡ Testing OLD way (GenServer.call, bypassing cache)...")

      # Get the client PID for direct calls
      client_pid = Teiserver.Account.ClientLib.get_client_pid(test_id)

      if client_pid do
        {genserver_time, _} =
          :timer.tc(fn ->
            Enum.each(1..iterations, fn _ ->
              # Direct GenServer.call, bypassing the cache
              GenServer.call(client_pid, :get_client_state)
            end)
          end)

        # Calculate metrics
        ets_time_ms = ets_time / 1000
        genserver_time_ms = genserver_time / 1000

        ets_per_second = iterations / (ets_time_ms / 1000)
        genserver_per_second = iterations / (genserver_time_ms / 1000)

        ets_avg_us = ets_time / iterations
        genserver_avg_us = genserver_time / iterations

        speedup = genserver_time_ms / ets_time_ms

        Logger.info("")
        Logger.info("✅ Benchmark Results:")
        Logger.info(String.duplicate("-", 62))
        Logger.info("  Iterations:        #{:erlang.integer_to_binary(iterations) |> String.pad_leading(10, " ")}")
        Logger.info("")
        Logger.info("  NEW (ETS Cache):")
        Logger.info("    Total time:        #{Float.round(ets_time_ms, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")} ms")
        Logger.info("    Lookups/sec:       #{Float.round(ets_per_second, 0) |> :erlang.float_to_binary(decimals: 0) |> String.pad_leading(10, " ")}")
        Logger.info("    Avg latency:      #{Float.round(ets_avg_us, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")} μs")
        Logger.info("")
        Logger.info("  OLD (GenServer.call):")
        Logger.info("    Total time:        #{Float.round(genserver_time_ms, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")} ms")
        Logger.info("    Lookups/sec:       #{Float.round(genserver_per_second, 0) |> :erlang.float_to_binary(decimals: 0) |> String.pad_leading(10, " ")}")
        Logger.info("    Avg latency:      #{Float.round(genserver_avg_us, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")} μs")
        Logger.info("")
        Logger.info("  🚀 IMPROVEMENT:")
        Logger.info("    Speedup:           #{Float.round(speedup, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")}x faster")
        Logger.info("    Time saved:        #{Float.round(genserver_time_ms - ets_time_ms, 2) |> :erlang.float_to_binary(decimals: 2) |> String.pad_leading(10, " ")} ms")
        Logger.info("")

        # Performance assessment
        cond do
          speedup > 50 ->
            Logger.info("🎉 Excellent improvement! (>#{Float.round(speedup, 0)}x faster)")
          speedup > 10 ->
            Logger.info("✅ Great improvement! (>#{Float.round(speedup, 0)}x faster)")
          speedup > 2 ->
            Logger.info("✅ Good improvement! (>#{Float.round(speedup, 0)}x faster)")
          true ->
            Logger.warning("⚠️  Modest improvement. May need investigation.")
        end

        Logger.info("")
      else
        Logger.warning("⚠️  Could not find client PID for direct GenServer.call test")
        Logger.info("   This means the client might not be connected or the process is down")
        Logger.info("")
      end
    end
  end
end

# Run if executed directly
ComparisonBenchmark.run()
