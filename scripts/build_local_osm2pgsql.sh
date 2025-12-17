#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
DOCKERFILE="$ROOT_DIR/docker/osm2pgsql.Dockerfile"
IMAGE_NAME=${IMAGE_NAME:-local/osm2pgsql:latest}

echo "Building local osm2pgsql image: $IMAGE_NAME"
docker build -f "$DOCKERFILE" -t "$IMAGE_NAME" "$ROOT_DIR"
echo "Built $IMAGE_NAME"
