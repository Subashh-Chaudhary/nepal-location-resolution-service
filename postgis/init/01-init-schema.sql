-- PostGIS Initialization Script for Nepal OSM Data
-- This script runs automatically when the container is first created

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS hstore;  -- Useful for OSM tags

-- Create schema for OSM data
CREATE SCHEMA IF NOT EXISTS osm;

-- ===========================================
-- OSM Nodes Table (Points)
-- ===========================================
CREATE TABLE IF NOT EXISTS osm.nodes (
    id BIGINT PRIMARY KEY,
    geom GEOMETRY(Point, 4326),
    tags HSTORE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_nodes_geom ON osm.nodes USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_nodes_tags ON osm.nodes USING GIN (tags);

-- ===========================================
-- OSM Ways Table (Lines/Polygons)
-- ===========================================
CREATE TABLE IF NOT EXISTS osm.ways (
    id BIGINT PRIMARY KEY,
    geom GEOMETRY(Geometry, 4326),
    tags HSTORE,
    nodes BIGINT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ways_geom ON osm.ways USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_ways_tags ON osm.ways USING GIN (tags);

-- ===========================================
-- Places Table (Searchable Locations)
-- ===========================================
CREATE TABLE IF NOT EXISTS osm.places (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT,
    osm_type VARCHAR(10),  -- 'node', 'way', 'relation'
    name VARCHAR(255),
    name_ne VARCHAR(255),  -- Nepali name
    place_type VARCHAR(50),  -- city, village, district, etc.
    admin_level INTEGER,
    geom GEOMETRY(Geometry, 4326),
    centroid GEOMETRY(Point, 4326),
    tags HSTORE,
    province VARCHAR(100),
    district VARCHAR(100),
    municipality VARCHAR(100),
    ward INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_places_geom ON osm.places USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_places_centroid ON osm.places USING GIST (centroid);
CREATE INDEX IF NOT EXISTS idx_places_name ON osm.places (name);
CREATE INDEX IF NOT EXISTS idx_places_name_ne ON osm.places (name_ne);
CREATE INDEX IF NOT EXISTS idx_places_place_type ON osm.places (place_type);
CREATE INDEX IF NOT EXISTS idx_places_tags ON osm.places USING GIN (tags);

-- ===========================================
-- Administrative Boundaries
-- ===========================================
CREATE TABLE IF NOT EXISTS osm.admin_boundaries (
    id SERIAL PRIMARY KEY,
    osm_id BIGINT,
    name VARCHAR(255),
    name_ne VARCHAR(255),
    admin_level INTEGER,  -- 4=province, 5=district, 6=municipality, 9=ward
    boundary_type VARCHAR(50),
    geom GEOMETRY(MultiPolygon, 4326),
    centroid GEOMETRY(Point, 4326),
    tags HSTORE,
    parent_id INTEGER REFERENCES osm.admin_boundaries(id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_geom ON osm.admin_boundaries USING GIST (geom);
CREATE INDEX IF NOT EXISTS idx_admin_centroid ON osm.admin_boundaries USING GIST (centroid);
CREATE INDEX IF NOT EXISTS idx_admin_level ON osm.admin_boundaries (admin_level);
CREATE INDEX IF NOT EXISTS idx_admin_name ON osm.admin_boundaries (name);

-- ===========================================
-- Sync Log Table
-- ===========================================
CREATE TABLE IF NOT EXISTS osm.sync_log (
    id SERIAL PRIMARY KEY,
    sync_type VARCHAR(50),
    status VARCHAR(20),
    records_processed INTEGER,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT
);

-- ===========================================
-- Sample Data (for testing)
-- ===========================================
INSERT INTO osm.places (osm_id, osm_type, name, name_ne, place_type, admin_level, centroid, province, district)
VALUES 
    (1, 'node', 'Kathmandu', 'काठमाडौं', 'city', 4, ST_SetSRID(ST_MakePoint(85.3240, 27.7172), 4326), 'Bagmati', 'Kathmandu'),
    (2, 'node', 'Pokhara', 'पोखरा', 'city', 4, ST_SetSRID(ST_MakePoint(83.9856, 28.2096), 4326), 'Gandaki', 'Kaski'),
    (3, 'node', 'Lalitpur', 'ललितपुर', 'city', 4, ST_SetSRID(ST_MakePoint(85.3206, 27.6588), 4326), 'Bagmati', 'Lalitpur'),
    (4, 'node', 'Bhaktapur', 'भक्तपुर', 'city', 4, ST_SetSRID(ST_MakePoint(85.4298, 27.6710), 4326), 'Bagmati', 'Bhaktapur'),
    (5, 'node', 'Biratnagar', 'विराटनगर', 'city', 4, ST_SetSRID(ST_MakePoint(87.2718, 26.4525), 4326), 'Province 1', 'Morang')
ON CONFLICT DO NOTHING;

-- Grant permissions
GRANT ALL PRIVILEGES ON SCHEMA osm TO osm_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA osm TO osm_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA osm TO osm_user;

-- Log successful initialization
INSERT INTO osm.sync_log (sync_type, status, records_processed, started_at, completed_at)
VALUES ('init', 'success', 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

-- Verify PostGIS version
SELECT PostGIS_Version();
