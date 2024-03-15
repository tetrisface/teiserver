#!/bin/bash
# Docker entrypoint script.

# Wait until Postgres is ready
echo "Testing if Postgres is accepting connections."
while ! pg_isready -q -h $POSTGRES_HOST -p $POSTGRES_PORT -U $POSTGRES_USER
do
  echo "$(date) - waiting for database to start"
  sleep 2
done

# Create, migrate, and seed database if it doesn't exist.
if [[ -z `psql -Atqc "\\list $POSTGRES_DB"` ]]; then
  echo "Database $POSTGRES_DB does not exist. Creating..."
#   psql -c "CREATE DATABASE $POSTGRES_DB;"
  psql -U $POSTGRES_USER -d $POSTGRES_DB -a -f ./dev.sql

  mix ecto.create
  mix ecto.migrate
  echo "Database $POSTGRES_DB created."
fi

exec mix phx.server