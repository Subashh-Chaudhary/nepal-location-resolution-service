-- INITIAL NORMALIZATION SQL
-- Target DB: nepal_location_pg
-- Run this after osm2pgsql import completes (it reads from planet_osm_* tables)

BEGIN;

CREATE SCHEMA IF NOT EXISTS normalized;

-- ADMIN BOUNDARIES (polygons from planet_osm_polygon)
CREATE TABLE IF NOT EXISTS normalized.admin_boundaries (
  id SERIAL PRIMARY KEY,
  osm_id BIGINT,
  name TEXT,
  name_ne TEXT,
  admin_level INTEGER,
  boundary_type TEXT,
  tags HSTORE,
  geom GEOMETRY(MultiPolygon,4326),
  centroid GEOMETRY(Point,4326),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS n_idx_admin_geom ON normalized.admin_boundaries USING GIST (geom);
CREATE INDEX IF NOT EXISTS n_idx_admin_centroid ON normalized.admin_boundaries USING GIST (centroid);
CREATE INDEX IF NOT EXISTS n_idx_admin_level ON normalized.admin_boundaries (admin_level);
CREATE INDEX IF NOT EXISTS n_idx_admin_name ON normalized.admin_boundaries (name);
CREATE INDEX IF NOT EXISTS n_idx_admin_tags ON normalized.admin_boundaries USING GIN (tags);

-- PLACES (points + polygon centroids)
CREATE TABLE IF NOT EXISTS normalized.places (
  id SERIAL PRIMARY KEY,
  osm_id BIGINT,
  osm_type VARCHAR(10), -- node/way/relation
  name TEXT,
  name_ne TEXT,
  place_type TEXT,
  admin_level INTEGER,
  tags HSTORE,
  geom GEOMETRY(Point,4326),
  centroid GEOMETRY(Point,4326),
  province TEXT,
  district TEXT,
  municipality TEXT,
  ward INTEGER,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS n_idx_places_geom ON normalized.places USING GIST (geom);
CREATE INDEX IF NOT EXISTS n_idx_places_centroid ON normalized.places USING GIST (centroid);
CREATE INDEX IF NOT EXISTS n_idx_places_name ON normalized.places (name);
CREATE INDEX IF NOT EXISTS n_idx_places_tags ON normalized.places USING GIN (tags);

-- NAMED ROADS
CREATE TABLE IF NOT EXISTS normalized.named_roads (
  id SERIAL PRIMARY KEY,
  osm_id BIGINT,
  name TEXT,
  tags HSTORE,
  geom GEOMETRY(LineString,4326),
  length_m DOUBLE PRECISION,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS n_idx_roads_geom ON normalized.named_roads USING GIST (geom);
CREATE INDEX IF NOT EXISTS n_idx_roads_name ON normalized.named_roads (name);

-- POI (points of interest not classified as places)
CREATE TABLE IF NOT EXISTS normalized.poi (
  id SERIAL PRIMARY KEY,
  osm_id BIGINT,
  name TEXT,
  tags HSTORE,
  geom GEOMETRY(Point,4326),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS n_idx_poi_geom ON normalized.poi USING GIST (geom);
CREATE INDEX IF NOT EXISTS n_idx_poi_name ON normalized.poi (name);
CREATE INDEX IF NOT EXISTS n_idx_poi_tags ON normalized.poi USING GIN (tags);

-- Clear existing normalized data (idempotent refresh)
TRUNCATE normalized.admin_boundaries, normalized.places, normalized.named_roads, normalized.poi RESTART IDENTITY;

-- Populate admin_boundaries from planet_osm_polygon (admin_level present)
INSERT INTO normalized.admin_boundaries (osm_id, name, name_ne, admin_level, boundary_type, tags, geom, centroid)
SELECT
  osm_id,
  COALESCE(name, tags->'name') AS name,
  COALESCE(tags->'name:ne', NULL) AS name_ne,
  (CASE
     WHEN tags ? 'admin_level' THEN NULLIF(tags->'admin_level','')::INTEGER
     WHEN admin_level IS NOT NULL THEN NULLIF(admin_level::text,'')::INTEGER
     ELSE NULL END) AS admin_level,
  COALESCE(boundary, tags->'boundary') AS boundary_type,
  tags::hstore AS tags,
  ST_Transform(ST_Multi(way),4326) AS geom,
  ST_Transform(ST_Centroid(ST_Multi(way)),4326) AS centroid
FROM planet_osm_polygon
WHERE (tags ? 'admin_level') OR (tags ? 'boundary') OR admin_level IS NOT NULL OR boundary IS NOT NULL;

-- Populate places: nodes with place tag or place column
INSERT INTO normalized.places (osm_id, osm_type, name, name_ne, place_type, admin_level, tags, geom, centroid)
SELECT
  osm_id,
  'node' AS osm_type,
  COALESCE(name, tags->'name') AS name,
  COALESCE(tags->'name:ne', NULL) AS name_ne,
  COALESCE(place, tags->'place') AS place_type,
  (CASE
     WHEN tags ? 'admin_level' THEN NULLIF(tags->'admin_level','')::INTEGER
     WHEN admin_level IS NOT NULL THEN NULLIF(admin_level::text,'')::INTEGER
     ELSE NULL END) AS admin_level,
  tags::hstore AS tags,
  ST_Transform(way,4326) AS geom,
  ST_Transform(way,4326) AS centroid
FROM planet_osm_point
WHERE (place IS NOT NULL) OR (tags ? 'place');

-- Also add polygon places (centroid)
INSERT INTO normalized.places (osm_id, osm_type, name, name_ne, place_type, admin_level, tags, geom, centroid)
SELECT
  osm_id,
  'way' AS osm_type,
  COALESCE(name, tags->'name') AS name,
  COALESCE(tags->'name:ne', NULL) AS name_ne,
  COALESCE(place, tags->'place') AS place_type,
  (CASE
     WHEN tags ? 'admin_level' THEN NULLIF(tags->'admin_level','')::INTEGER
     WHEN admin_level IS NOT NULL THEN NULLIF(admin_level::text,'')::INTEGER
     ELSE NULL END) AS admin_level,
  tags::hstore AS tags,
  ST_Transform(ST_Centroid(ST_Multi(way)),4326) AS geom,
  ST_Transform(ST_Centroid(ST_Multi(way)),4326) AS centroid
FROM planet_osm_polygon
WHERE (place IS NOT NULL) OR (tags ? 'place');

-- Named roads: ways with a name and highway tag (use dedicated columns if present)
INSERT INTO normalized.named_roads (osm_id, name, tags, geom, length_m)
SELECT
  osm_id,
  COALESCE(name, tags->'name') AS name,
  tags::hstore AS tags,
  (ST_Transform(ST_LineMerge(ST_Multi(way)),4326))::geometry(LineString,4326) AS geom,
  ST_Length(ST_Transform(ST_LineMerge(ST_Multi(way)), 3857)) AS length_m
FROM planet_osm_line
WHERE ( (highway IS NOT NULL) OR (tags ? 'highway') ) AND ( (name IS NOT NULL) OR (tags ? 'name') );

-- POIs: points with a name and not a 'place'
INSERT INTO normalized.poi (osm_id, name, tags, geom)
SELECT
  osm_id,
  COALESCE(name, tags->'name') AS name,
  tags::hstore AS tags,
  ST_Transform(way,4326) AS geom
FROM planet_osm_point
WHERE ( (name IS NOT NULL) OR (tags ? 'name') ) AND NOT ( (place IS NOT NULL) OR (tags ? 'place') );

CREATE INDEX IF NOT EXISTS n_idx_admin_boundaries_admin_level ON normalized.admin_boundaries (admin_level);

-- Update places with province
UPDATE normalized.places p
SET province = a.name
FROM normalized.admin_boundaries a
WHERE a.admin_level = 4
  AND ST_Intersects(a.geom, COALESCE(p.centroid, p.geom));

-- Update places with district (admin_level = 6)
UPDATE normalized.places p
SET district = a.name
FROM normalized.admin_boundaries a
WHERE a.admin_level = 6
  AND ST_Intersects(a.geom, COALESCE(p.centroid, p.geom));

-- Update places with municipality (admin_level = 7)
UPDATE normalized.places p
SET municipality = a.name
FROM normalized.admin_boundaries a
WHERE a.admin_level = 7
  AND ST_Intersects(a.geom, COALESCE(p.centroid, p.geom));

-- Update places with ward (admin_level 9)
UPDATE normalized.places p
SET ward = COALESCE(
    NULLIF(a.tags->'ward','')::INTEGER,
    NULLIF(a.tags->'ref','')::INTEGER
  )
FROM normalized.admin_boundaries a
WHERE a.admin_level = 9
  AND ST_Intersects(a.geom, COALESCE(p.centroid, p.geom));

-- Analyze normalized tables for planner
ANALYZE normalized.admin_boundaries;
ANALYZE normalized.places;
ANALYZE normalized.named_roads;
ANALYZE normalized.poi;

COMMIT;

-- Verification helper queries (copy/paste into psql or DBeaver):
-- SELECT COUNT(*) FROM normalized.places;
-- SELECT COUNT(*) FROM normalized.admin_boundaries WHERE admin_level=6; -- districts
-- SELECT name, province, district FROM normalized.places WHERE name IS NOT NULL LIMIT 20;
