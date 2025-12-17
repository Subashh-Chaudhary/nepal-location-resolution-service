#!/usr/bin/env bash
set -euo pipefail

# Usage: edit variables below or set them in environment before running
PBF_PATH=${PBF_PATH:-"/home/subashtharu/Desktop/ninja/nepal-location-resolution-service/nepal-251216.osm.pbf"}
FLAT_DIR=${FLAT_DIR:-"/var/tmp"}
FLAT_NAME=${FLAT_NAME:-"nepal-flatnodes.bin"}
CACHE_MB=${CACHE_MB:-6144}
PROCS=${PROCS:-4}
DB_NAME=${DB_NAME:-nepal_location_pg}
DB_HOST=${DB_HOST:-127.0.0.1}
DB_PORT=${DB_PORT:-5433}
DB_USER=${DB_USER:-osm_user}
DB_PASS=${DB_PASS:-osm_secret_password}
IMAGE_NAME=${IMAGE_NAME:-local/osm2pgsql:latest}

if [ ! -f "$PBF_PATH" ]; then
  echo "PBF not found at $PBF_PATH"
  exit 1
fi

mkdir -p "$FLAT_DIR"

echo "Running import with image $IMAGE_NAME"
docker run --rm -it \
  -v "$PBF_PATH":/data/nepal.osm.pbf \
  -v "$FLAT_DIR":/data/flat \
  --network host \
  -e PGPASSWORD="$DB_PASS" \
  "$IMAGE_NAME" \
  --slim --hstore --extra-attributes --flat-nodes /data/flat/$FLAT_NAME --cache $CACHE_MB --number-processes $PROCS -d $DB_NAME -U $DB_USER -H $DB_HOST -P $DB_PORT /data/nepal.osm.pbf
