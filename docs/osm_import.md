# OSM Import & Initial Normalization — Guide

This document describes the recommended, repeatable steps to import `nepal-251216.osm.pbf` into PostGIS and run the INITIAL NORMALIZATION stage for the Nepal Location Resolution Service.

Summary of the PBF (from `osmium fileinfo`):
- Nodes: 69,045,765
- Ways: 9,369,264
- Relations: 20,033
- File size: ~406 MB (buffers indicate ~5.7GB processing)

High-level plan
1. Create target database `nepal_location_pg` and enable `postgis`, `hstore`, and `pg_trgm`.
2. Import the PBF using `osm2pgsql --slim` with `--hstore` and `--extra-attributes`.
3. Run the normalization SQL (`sql/normalize_initial.sql`).
4. Run spatial enrichment queries (ST_Contains/ST_Intersects) to attach admin hierarchies.
5. Verify counts and sample rows.

Important notes and resource recommendations
- This PBF will allocate significant temporary disk I/O and memory. Recommended:
  - At least 16 GB RAM available on the host (8–12 GB usable cache for osm2pgsql).
  - At least 50 GB free disk (for DB, indexes, and `flat-nodes` file). The exact requirement depends on import options.
  - Use `--flat-nodes` stored on an SSD if possible to speed up processing.

Recommended osm2pgsql options (example tuned for this dataset):

Host/native (preferred when `osm2pgsql` is installed locally):

```bash
# create flat nodes file path and variables (adjust cache value to your RAM)
FLAT_NODES=/var/tmp/nepal-flatnodes.bin
PBF_PATH=/path/to/nepal-251216.osm.pbf
CACHE_MB=8192   # adjust to available RAM (e.g., 6144, 8192, 12288)
PROCS=4         # adjust to number of CPU cores

osm2pgsql \
  --slim \
  --hstore \
  --extra-attributes \
  --flat-nodes "$FLAT_NODES" \
  --cache $CACHE_MB \
  --number-processes $PROCS \
  -d nepal_location_pg \
  -U postgres -H localhost -P 5433 \
  "$PBF_PATH"
```

Docker fallback (if `osm2pgsql` is not available locally):

```bash
# This runs an ephemeral Ubuntu container, installs osm2pgsql and runs the import.
# It mounts your PBF and a local folder for the flat-nodes file.

PBF_PATH=/full/path/to/nepal-251216.osm.pbf
FLAT_DIR=/full/path/to/flat_nodes_dir
CACHE_MB=8192
PROCS=4

docker run --rm -it \
  -v "$PBF_PATH":/data/nepal.osm.pbf \
  -v "$FLAT_DIR":/data/flat \
  --network host \
  ubuntu:22.04 bash -c "\
    apt-get update && apt-get install -y osm2pgsql postgresql-client && \
    osm2pgsql --slim --hstore --extra-attributes --flat-nodes /data/flat/nepal-flatnodes.bin \
      --cache $CACHE_MB --number-processes $PROCS -d nepal_location_pg -U postgres -H 127.0.0.1 -P 5433 /data/nepal.osm.pbf"
```

Notes about connecting to PostGIS in Docker Compose
- If your PostGIS service is the one in this repo's `docker-compose.yml`, the container is named `postgis` and listens on internal port `5432`. From the host you can connect to the container via host port `5433` (this repo maps `5433:5432`). Use `-h localhost -p 5433` or `-h 127.0.0.1 -p 5433` for psql/osm2pgsql on the host.
- From a container on the same compose network, use `-h postgis -p 5432`.

Create the database and extensions (two options)

Option A — using `docker compose exec` (recommended when compose is running):

```bash
docker compose exec postgis psql -U postgres -c "CREATE DATABASE nepal_location_pg;"
docker compose exec -T postgis psql -U postgres -d nepal_location_pg -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
```

Option B — using `psql` from host (if Postgres is exposed on host port 5433):

```bash
PGPASSWORD=your_password psql -h 127.0.0.1 -p 5433 -U postgres -c "CREATE DATABASE nepal_location_pg;"
PGPASSWORD=your_password psql -h 127.0.0.1 -p 5433 -U postgres -d nepal_location_pg -c "CREATE EXTENSION IF NOT EXISTS postgis; CREATE EXTENSION IF NOT EXISTS hstore; CREATE EXTENSION IF NOT EXISTS pg_trgm;"
```

Post-import: run normalization SQL

After osm2pgsql finishes and `planet_osm_*` (or `nodes/ways` tables depending on options) exist, run the normalization SQL prepared in the repo:

```bash
psql -h 127.0.0.1 -p 5433 -U postgres -d nepal_location_pg -f sql/normalize_initial.sql
```

Verification queries (quick checks)

```sql
-- counts (run with psql)
SELECT COUNT(*) FROM planet_osm_point;
SELECT COUNT(*) FROM planet_osm_line;
SELECT COUNT(*) FROM planet_osm_polygon;

-- sample places
SELECT osm_id, name, place, ST_AsText(way) FROM planet_osm_point WHERE name IS NOT NULL LIMIT 10;

-- check indexes
SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'public';
```

Next steps
- Execute the `scripts/create_postgis_db.sh` script to create DB & extensions.
- Run `scripts/import_with_osm2pgsql.sh` (edit top env vars) to perform the import.
- After import, run normalization SQL and run the verification queries.

If you'd like, I can run the DB creation now (I can exec into the running PostGIS container) — tell me whether you want me to run the import here (I will need the PBF to be available to the environment or confirm you want the Docker fallback run on your machine).
