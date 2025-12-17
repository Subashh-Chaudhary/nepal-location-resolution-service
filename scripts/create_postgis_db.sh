#!/usr/bin/env bash
# Create the target PostGIS database `nepal_location_pg` and enable extensions.
# Usage: ./scripts/create_postgis_db.sh

set -euo pipefail

# Try docker compose exec into the postgis container first
if docker compose ps postgis >/dev/null 2>&1; then
  echo "Creating database inside running postgis container..."
  docker compose exec postgis psql -U postgres -c "CREATE DATABASE nepal_location_pg;" || true
  docker compose exec -T postgis psql -U postgres -d nepal_location_pg -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
  echo "Database created and extensions enabled (via docker compose exec)."
  exit 0
fi

echo "docker compose doesn't appear to be running or postgis service not found. Trying host psql (127.0.0.1:5433)."

# Fallback: try to use psql on host (Postgres exposed on host 5433 in this repo)
if command -v psql >/dev/null 2>&1; then
  echo "Using host psql. Ensure Postgres is listening on 127.0.0.1:5433 and PGPASSWORD is set if needed."
  PSQL_HOST=${PSQL_HOST:-127.0.0.1}
  PSQL_PORT=${PSQL_PORT:-5433}
  PSQL_USER=${PSQL_USER:-postgres}
  psql -h "$PSQL_HOST" -p "$PSQL_PORT" -U "$PSQL_USER" -c "CREATE DATABASE nepal_location_pg;" || true
  psql -h "$PSQL_HOST" -p "$PSQL_PORT" -U "$PSQL_USER" -d nepal_location_pg -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
  echo "Database created and extensions enabled (via host psql)."
  exit 0
fi

echo "No suitable method available to create DB. Install docker compose or psql and try again."
exit 2
