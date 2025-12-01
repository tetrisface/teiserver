#!/bin/bash
set -e

echo "🚀 Starting Teiserver development setup..."

# Wait for postgres to be ready
echo "⏳ Waiting for PostgreSQL..."
until pg_isready -h "$POSTGRES_HOSTNAME" -U "$POSTGRES_USER"; do
  sleep 1
done
echo "✅ PostgreSQL is ready"

# Create database (mix ecto.create is idempotent - won't fail if it exists)
echo "📦 Creating database (if needed)..."
mix ecto.create || echo "⚠️  Database already exists or creation skipped"
echo "✅ Database step complete"

# Run migrations
echo "🔄 Running migrations..."
mix ecto.migrate
echo "✅ Migrations complete"

# Install SASS (needed for CSS generation, skip for tests)
# Debug: Show MIX_ENV
echo "Current MIX_ENV: $MIX_ENV"

if [ "$MIX_ENV" = "test" ]; then
  echo "⏭️  Skipping SASS installation (test mode)"
elif [ ! -d "assets/node_modules/sass" ]; then
  echo "🎨 Installing SASS..."
  mix sass.install || echo "⚠️  SASS installation failed (non-fatal)"
  echo "✅ SASS installed"
else
  echo "✅ SASS already installed"
fi

# Optional: Generate fake data for development
if [ "$GENERATE_FAKE_DATA" = "true" ]; then
  echo "🎭 Generating fake data..."
  mix teiserver.fakedata
  echo "✅ Fake data generated"
fi

# Setup root user, OAuth, and test users (run AFTER fake data to ensure verified flags are set)
# Skip for tests (test_helper.exs handles test setup)
if [ "$MIX_ENV" != "test" ]; then
  echo "🔧 Setting up dev environment..."
  mix teiserver.dev_setup
else
  echo "⏭️  Skipping dev setup (test mode)"
fi

echo ""
echo "🎉 Setup complete!"

# Check if we should start the server (skip if PHX_SERVER is false or if command is not phx.server)
if [ "$PHX_SERVER" != "false" ] && echo "$@" | grep -q "phx.server"; then
  echo "Starting Phoenix server..."
  echo ""
  echo "📍 Access points:"
  echo "   Web UI:  http://localhost:8080"
  echo "   Tachyon: ws://localhost:8200"
  echo ""
  echo "👤 Test credentials:"
  echo "   test_email_1   / password"
  echo "   test_email_2  / password"
  echo "   root@localhost   / password (admin)"
  echo ""
fi

# Execute the command (or start server if no command provided)
exec "$@"

