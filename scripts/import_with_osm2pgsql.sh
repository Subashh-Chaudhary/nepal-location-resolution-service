#!/usr/bin/env bash
# Import the nepal-251216.osm.pbf into PostGIS using osm2pgsql.
# Edit the variables below before running.

set -euo pipefail

# === Config (edit as needed) ===
PBF_PATH=${PBF_PATH:-"/full/path/to/nepal-251216.osm.pbf"}
FLAT_NODES=${FLAT_NODES:-"/var/tmp/nepal-flatnodes.bin"}
CACHE_MB=${CACHE_MB:-8192}
PROCS=${PROCS:-4}
DB_NAME=${DB_NAME:-nepal_location_pg}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-5433}
DB_USER=${DB_USER:-postgres}

echo "PBF_PATH=$PBF_PATH"
echo "FLAT_NODES=$FLAT_NODES"
echo "CACHE_MB=$CACHE_MB PROCS=$PROCS"

if [ ! -f "$PBF_PATH" ]; then
  echo "ERROR: PBF file not found at $PBF_PATH"
  exit 1
fi

# If osm2pgsql exists on host, use it (preferred)
if command -v osm2pgsql >/dev/null 2>&1; then
  echo "Using host osm2pgsql. Make sure Postgres is accepting connections on $DB_HOST:$DB_PORT"
  mkdir -p "$(dirname "$FLAT_NODES")"
  osm2pgsql \
    --slim \
    --hstore \
    --extra-attributes \
    --flat-nodes "$FLAT_NODES" \
    --cache $CACHE_MB \
    --number-processes $PROCS \
    -d "$DB_NAME" \
    -U "$DB_USER" -H "$DB_HOST" -P "$DB_PORT" \
    "$PBF_PATH"
  echo "Import finished (host osm2pgsql)."
  exit 0
fi

echo "osm2pgsql not found on host — using Docker fallback. This will install inside an ephemeral Ubuntu container."

if [ ! -d "$(dirname "$FLAT_NODES")" ]; then
  mkdir -p "$(dirname "$FLAT_NODES")"
fi

# Use --network host so the container can reach host Postgres at 127.0.0.1:5433
docker run --rm -it \
  -v "$PBF_PATH":/data/nepal.osm.pbf \
  -v "$(dirname "$FLAT_NODES")":/data/flat \
  --network host \
  ubuntu:22.04 bash -c "\
    set -e && apt-get update && apt-get install -y osm2pgsql postgresql-client && \
    osm2pgsql --slim --hstore --extra-attributes --flat-nodes /data/flat/$(basename "$FLAT_NODES") \
      --cache $CACHE_MB --number-processes $PROCS -d $DB_NAME -U $DB_USER -H $DB_HOST -P $DB_PORT /data/nepal.osm.pbf"

echo "Import finished (docker fallback)."
