.PHONY: docker-test docker-benchmark docker-benchmark-comparison

docker-test:
	# Start postgres if not running
	docker compose up -d postgres
	# Wait for postgres to be ready
	@echo "⏳ Waiting for PostgreSQL..."
	@timeout 30 bash -c 'until docker compose exec -T postgres pg_isready -U teiserver; do sleep 1; done' || true
	# Run tests in a one-off container (doesn't start web server)
	# Using 'run' instead of 'up' creates a temporary container that exits after the command
	# MIX_ENV=test ensures test config is used (with SQL Sandbox)
	# POSTGRES_* vars point to the postgres service in docker-compose
	# PHX_SERVER=false prevents the entrypoint from starting the web server
	MIX_ENV=test docker compose run --rm \
		-e MIX_ENV=test \
		-e PHX_SERVER=false \
		-e POSTGRES_HOSTNAME=postgres \
		-e POSTGRES_USER=teiserver \
		-e POSTGRES_PASSWORD=teiserver_dev_password \
		-e POSTGRES_DB=teiserver_test \
		teiserver sh -c "cd /app && mix ecto.create -r Teiserver.Repo || true && mix test"

docker-benchmark:
	docker-compose exec -T teiserver sh -c "cd /app && elixir -e 'Code.eval_file(\"scripts/benchmark_client_lookup_comparison.exs\")'"

docker-benchmark-comparison:
	docker-compose exec -T teiserver sh -c "cd /app && elixir -e 'Code.eval_file(\"scripts/benchmark_client_lookup_comparison.exs\")'"
