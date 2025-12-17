# Nepal Location Resolution — Full Data Pipeline & Normalization Guide

This document explains, in detail, the full OSM → PostGIS → normalized schema pipeline used in this repository. It documents every step we ran, why we ran it, how the data maps from `osm2pgsql`'s `planet_osm_*` tables into our `normalized.*` tables, and how to inspect and troubleshoot the data. Use this as the canonical reference for imports and normalization.

## Contents
- Overview
- Architecture & files touched
- PostGIS database creation & init scripts
- Import: osm2pgsql options and why
- What osm2pgsql produces (planet_osm_* tables)
- Normalization: `sql/normalize_initial.sql` walk-through
- Spatial enrichment (admin joins, wards)
- Indexing and performance notes
- Scripts and Dockerfile added to repo
- Verification & troubleshooting checks
- Next steps (ES mapping and export)

## Overview
Goal: import `nepal-251216.osm.pbf`, normalize OSM features into a compact, queryable PostGIS schema, and enrich records with admin hierarchy (province, district, municipality, ward) so downstream services or Elasticsearch can consume denormalized documents.

We split the work into phases:
1. Import raw OSM data into PostGIS via `osm2pgsql` (slim mode). This produces `planet_osm_point`, `planet_osm_line`, `planet_osm_polygon`, and `planet_osm_roads` tables.
2. Run normalization SQL (`sql/normalize_initial.sql`) that reads `planet_osm_*` tables and creates `normalized.admin_boundaries`, `normalized.places`, `normalized.named_roads`, and `normalized.poi`.
3. Run spatial enrichment to attach admin hierarchy fields to places and POIs.

## Architecture & files
- `docker-compose.yml` — runs the `postgis` container exposing host port `5433` and mounts `postgis/init/01-init-schema.sql` for DB initialization.
- `postgis/init/01-init-schema.sql` — initial schema used when the PostGIS container was first created (sample `osm.*` schema and sample rows).
- `docker/osm2pgsql.Dockerfile` — a small Debian-based image that installs `osm2pgsql` & `postgresql-client` for deterministic local imports.
- `scripts/`:
  - `build_local_osm2pgsql.sh` — builds the local osm2pgsql image.
  - `run_local_osm2pgsql.sh` — runs the import using the local image.
  - `create_postgis_db.sh` — convenience script to create `nepal_location_pg` and enable extensions.
- `sql/normalize_initial.sql` — the normalization script (added to repo and executed). See below for a line-by-line explanation.
- `docs/osm_import.md` — quick import notes and the fallback instructions.

## PostGIS database creation & init
We used a `postgis/postgis:16-3.4-alpine` container in `docker-compose.yml` and mounted `postgis/init/01-init-schema.sql` so the container ran that script on first startup.

Key points in init script (`postgis/init/01-init-schema.sql`):
- Enables `postgis`, `postgis_topology`, and `hstore` extensions.
- Creates a convenience `osm` schema with example `nodes`, `ways`, and `places` tables (this is separate from the `planet_osm_*` tables created by `osm2pgsql`).
- Inserts a few sample rows and grants privileges to `osm_user`.

When the database was created for the normalization target we created a dedicated DB named `nepal_location_pg` and enabled extensions there too:

```bash
docker compose exec postgis psql -U osm_user -c "CREATE DATABASE nepal_location_pg OWNER osm_user;"
docker compose exec -T postgis psql -U osm_user -d nepal_location_pg -c "CREATE EXTENSION postgis; CREATE EXTENSION hstore; CREATE EXTENSION pg_trgm;"
```

## Import: osm2pgsql options and why
We ran `osm2pgsql` with `--slim` to allow a larger dataset and keep data on disk, `--hstore` to preserve raw tags, and `--extra-attributes` to capture extra aux columns that osm2pgsql produces. Other important options:
- `--flat-nodes /path/to/flat.bin` — speeds up relation resolution and reduces memory footprint.
- `--cache <MB>` — memory cache for osm2pgsql (we used 6144 MB conservatively; 8–12GB recommended on beefier machines).
- `--number-processes <N>` — parallel workers. We used 4 on an 8-core machine.

Example (we used a locally-built image):

```bash
./scripts/run_local_osm2pgsql.sh
# The script mounts the PBF and flat dir, uses local image local/osm2pgsql:latest
```

## What osm2pgsql produces (planet_osm_* tables)
The `osm2pgsql` import creates several `planet_osm_*` tables in the target database. Typical tables are:
- `planet_osm_point` (points)
- `planet_osm_line` (lines)
- `planet_osm_polygon` (polygons)
- `planet_osm_roads` (subset of ways optimized for routing)

Each `planet_osm_*` table contains a set of dedicated columns for common OSM tags (osm2pgsql's default style), plus a `tags` column (type `hstore`) with all tags. Example columns we observed in the Nepal import (excerpt):

`osm_id, access, addr:housename, addr:housenumber, admin_level, amenity, highway, name, place, population, tags, way`

Notes:
- `tags` is an `hstore` of all raw tags (key=>value). We fall back on `tags` only when dedicated columns are not present.
- Dedicated columns (e.g., `place`, `admin_level`, `highway`) are faster to query than parsing `tags` hstore for every row.

## Normalization: `sql/normalize_initial.sql` walk-through
The normalization script performs the following steps (the file is in the repo at `sql/normalize_initial.sql`). High-level sequence:

1. Create schema `normalized` and tables: `admin_boundaries`, `places`, `named_roads`, `poi`.
   - Geometry columns are explicitly set to SRID 4326 to match `osm2pgsql` default geoms (we transform geometries when necessary).

2. Truncate normalized tables (idempotent refresh) so the script can be re-run safely.

3. Populate `normalized.admin_boundaries` from `planet_osm_polygon` where `admin_level` or `boundary` tags exist.
   - Uses dedicated `admin_level` and `boundary` columns if available, otherwise falls back to `tags->'admin_level'`.
   - Stores tags as `hstore` in `tags` column for later debugging.

4. Populate `normalized.places`:
   - From `planet_osm_point` and `planet_osm_polygon` for features with `place` information.
   - We use the dedicated `place`, `name`, and `admin_level` columns when present, otherwise fallback to `tags`.

5. Populate `normalized.named_roads` from `planet_osm_line` where `highway` and `name` exist.

6. Populate `normalized.poi` from `planet_osm_point` with a `name` but not a `place`.

7. Spatial enrichment: attach province/district/municipality/ward fields to `normalized.places` using spatial joins.
   - We use `ST_Intersects` for robustness (points on boundaries included) and match admin levels appropriate for Nepal (province=4, district=6, municipality=7, ward=9).
   - Ward numbers are extracted from `admin_boundaries.tags` using `regexp_replace` to ensure integer casting (some values contained non-digit characters or unicode digits).

8. `ANALYZE` the normalized tables to update planner statistics.

## Spatial enrichment (admin joins, wards)
- Use `ST_Intersects` rather than `ST_Contains` to avoid missing features that fall exactly on shared polygon boundaries.
- Admin level mapping for Nepal:
  - province: `admin_level = 4`
  - district: `admin_level = 6`
  - municipality: `admin_level = 7`
  - ward: `admin_level = 9`
- Ward extraction: many polygons store their ward number under `tags->'ward'` or `tags->'ref'` and occasionally with non-digit characters; the script pulls digits via `regexp_replace(..., '\\D', '', 'g')` and casts to integer.

## Indexing and performance notes
- GiST indexes on geometry columns are required for fast spatial joins. The script creates them on `normalized.admin_boundaries.geom` and `normalized.places.centroid`.
- Creating function or heavy btree indexes on large geometries is expensive; keep geometry indexing to GiST and use separate btree indexes for scalar columns (names, admin_level).
- When running spatial enrichment at scale, ensure Postgres has sufficient `work_mem` and `maintenance_work_mem`, and consider batching updates.

## Scripts and Dockerfile
- `docker/osm2pgsql.Dockerfile` — builds a Debian-based image that installs `osm2pgsql` and `postgresql-client` so imports can be run deterministically in air-gapped environments.
- `scripts/build_local_osm2pgsql.sh` — builds the image `local/osm2pgsql:latest`.
- `scripts/run_local_osm2pgsql.sh` — mounts the PBF and `flat-nodes` dir and runs the import with configured cache and processes.
- `scripts/create_postgis_db.sh` — convenience wrapper to create `nepal_location_pg` and enable extensions.

## Verification & troubleshooting
Basic checks (psql or DBeaver):

```sql
-- counts
SELECT 'places', COUNT(*) FROM normalized.places;
SELECT 'admin_boundaries', COUNT(*) FROM normalized.admin_boundaries;
SELECT admin_level, COUNT(*) FROM normalized.admin_boundaries GROUP BY admin_level ORDER BY admin_level;

-- sample rows
SELECT name, province, district, municipality, ward FROM normalized.places WHERE name IS NOT NULL LIMIT 20;

-- check raw imported tables
SELECT COUNT(*) FROM planet_osm_point;
SELECT COUNT(*) FROM planet_osm_polygon WHERE tags ? 'admin_level' OR tags ? 'boundary';
```

If some normalized tables are empty or low-count:
- Confirm `planet_osm_*` contains the expected tag keys. Use `SELECT COUNT(*) FROM planet_osm_point WHERE tags ? 'place';` and inspect `SELECT (tags->'place') FROM planet_osm_point LIMIT 10;`.
- Confirm SRID issues: errors about SRID mismatches indicate transforms are required (we already address this in the script using `ST_Transform`).

## DBeaver connection details
- Driver: PostgreSQL (use bundled driver)
- Host: `127.0.0.1`
- Port: `5433` (mapped in `docker-compose.yml`)
- Database: `nepal_location_pg`
- Username/password: `osm_user` / `osm_secret_password`

## Next steps: ES mapping and exporter
We can now denormalize `normalized.*` rows into Elasticsearch documents. Typical choices:
- `normalized.places` → one ES index `nepal-places` with fields: `name`, `name_ne`, `place_type`, `province`, `district`, `municipality`, `ward`, `location` (geo_point), `tags` (flattened object)
- Use analyzers in ES for Nepali and English names (standard + ICU/analysis where needed)

I can add:
- an `sql/export_to_es.sql` or a small Go/Python exporter that streams `normalized.places` as NDJSON for the ES bulk API
- an `docs/es_mapping.md` describing ES field types and analyzers

## Appendix: quick run commands
1. Build local osm2pgsql image:
```bash
./scripts/build_local_osm2pgsql.sh
```

2. Create DB and enable extensions (if not done):
```bash
./scripts/create_postgis_db.sh
```

3. Run osm2pgsql import:
```bash
./scripts/run_local_osm2pgsql.sh
```

4. Run normalization SQL:
```bash
PGPASSWORD=osm_secret_password psql -h 127.0.0.1 -p 5433 -U osm_user -d nepal_location_pg -f sql/normalize_initial.sql
```

If you want, I will now:
- produce the ES mapping and an exporter script, or
- add a README section with step-by-step screenshots/commands for DBeaver, or
- produce an export job (small Python) that streams normalized rows to Elasticsearch.

End of document.
