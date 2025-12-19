#!/usr/bin/env python3
"""
PostgreSQL to Elasticsearch Sync Script
Syncs normalized Nepal location data to Elasticsearch for fast search
"""

import os
import sys
import json
import logging
from typing import Dict, List, Optional
from datetime import datetime

import psycopg2
from psycopg2.extras import RealDictCursor
from elasticsearch import Elasticsearch, helpers

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class LocationSyncer:
    """Syncs location data from PostgreSQL to Elasticsearch"""
    
    def __init__(self):
        self.es_url = os.getenv('ELASTICSEARCH_URL', 'http://localhost:9200')
        self.es_index = os.getenv('ES_INDEX', 'nepal_locations')
        self.db_host = os.getenv('POSTGRES_HOST', 'localhost')
        self.db_port = os.getenv('POSTGRES_PORT', '5433')
        self.db_name = os.getenv('POSTGRES_DB', 'nepal_location_pg')
        self.db_user = os.getenv('POSTGRES_USER', 'osm_user')
        self.db_pass = os.getenv('POSTGRES_PASSWORD', 'osm_secret_password')
        
        # Initialize connections
        self.es = Elasticsearch([self.es_url])
        self.conn = None
        
    def connect_db(self):
        """Connect to PostgreSQL"""
        try:
            self.conn = psycopg2.connect(
                host=self.db_host,
                port=self.db_port,
                database=self.db_name,
                user=self.db_user,
                password=self.db_pass
            )
            logger.info(f"Connected to PostgreSQL at {self.db_host}:{self.db_port}/{self.db_name}")
        except Exception as e:
            logger.error(f"Failed to connect to PostgreSQL: {e}")
            raise
            
    def create_index(self):
        """Create Elasticsearch index with mapping"""
        # Try multiple paths for mapping file
        mapping_paths = [
            '/app/mappings/nepal_locations.json',  # Docker path
            os.path.join(os.path.dirname(__file__), '..', 'elasticsearch', 'mappings', 'nepal_locations.json'),  # Local path
        ]
        
        mapping_path = None
        for path in mapping_paths:
            if os.path.exists(path):
                mapping_path = path
                break
        
        # Try to load mapping from file, fallback to basic mapping
        try:
            with open(mapping_path, 'r') as f:
                mapping = json.load(f)
        except FileNotFoundError:
            logger.warning(f"Mapping file not found at {mapping_path}, using default")
            mapping = self._get_default_mapping()
        
        if self.es.indices.exists(index=self.es_index):
            logger.info(f"Index {self.es_index} already exists, deleting...")
            self.es.indices.delete(index=self.es_index)
            
        self.es.indices.create(index=self.es_index, body=mapping)
        logger.info(f"Created index: {self.es_index}")
        
    def _get_default_mapping(self) -> Dict:
        """Fallback default mapping"""
        return {
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 1
            },
            "mappings": {
                "properties": {
                    "entity_type": {"type": "keyword"},
                    "name": {"type": "text", "fields": {"keyword": {"type": "keyword"}}},
                    "location": {"type": "geo_point"},
                    "country": {"type": "keyword"}
                }
            }
        }
        
    def extract_admin_name(self, tags: Optional[Dict], default_name: str, lang: str = 'ne') -> Optional[str]:
        """Extract localized admin boundary names"""
        if not tags:
            return None
        return tags.get(f'name:{lang}', default_name)
        
    def sync_places(self) -> int:
        """Sync places from PostgreSQL"""
        query = """
        SELECT 
            'place_' || id::text as doc_id,
            'place' as entity_type,
            name,
            name_ne,
            place_type,
            admin_level,
            ST_Y(ST_Transform(geom, 4326)) as lat,
            ST_X(ST_Transform(geom, 4326)) as lon,
            ward,
            municipality,
            district,
            province,
            tags
        FROM normalized.places
        WHERE name IS NOT NULL
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            
            def generate_docs():
                for row in cur:
                    # Extract English names from tags if available
                    tags = row.get('tags')
                    if isinstance(tags, str):
                        # Parse HSTORE string format if needed
                        try:
                            import json
                            tags = json.loads(tags) if tags else {}
                        except:
                            tags = {}
                    elif tags is None:
                        tags = {}
                    
                    name_en = tags.get('name:en', row['name'])
                    
                    # Boost score based on entity type
                    boost = self._calculate_boost('place', row.get('place_type'))
                    
                    doc = {
                        '_index': self.es_index,
                        '_id': row['doc_id'],
                        '_source': {
                            'id': row['doc_id'],
                            'entity_type': row['entity_type'],
                            'name': row['name'],
                            'name_ne': row.get('name_ne'),
                            'name_en': name_en,
                            'place_type': row.get('place_type'),
                            'admin_level': row.get('admin_level'),
                            'location': {
                                'lat': row['lat'],
                                'lon': row['lon']
                            } if row.get('lat') else None,
                            'ward': row.get('ward'),
                            'municipality': row.get('municipality'),
                            'municipality_ne': row.get('municipality'),
                            'district': row.get('district'),
                            'district_ne': row.get('district'),
                            'province': row.get('province'),
                            'province_ne': row.get('province'),
                            'country': 'Nepal',
                            'boost_score': boost,
                            'search_text': self._build_search_text(row)
                        }
                    }
                    yield doc
                    
            success, failed = helpers.bulk(self.es, generate_docs(), raise_on_error=False)
            logger.info(f"Synced {success} places ({failed} failed)")
            return success
            
    def sync_admin_boundaries(self) -> int:
        """Sync administrative boundaries"""
        query = """
        SELECT 
            'admin_' || id::text as doc_id,
            'admin_boundary' as entity_type,
            name,
            name_ne,
            admin_level,
            boundary_type,
            ST_Y(ST_Transform(centroid, 4326)) as lat,
            ST_X(ST_Transform(centroid, 4326)) as lon,
            ST_AsText(ST_Transform(centroid, 4326)) as centroid,
            tags
        FROM normalized.admin_boundaries
        WHERE name IS NOT NULL
          AND admin_level IN (4, 6, 7, 9)  -- Province, District, Municipality, Ward
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            
            def generate_docs():
                for row in cur:
                    # Parse tags from HSTORE string format
                    tags = row.get('tags')
                    if isinstance(tags, str):
                        try:
                            import json
                            tags = json.loads(tags) if tags else {}
                        except:
                            tags = {}
                    elif tags is None:
                        tags = {}
                    name_en = tags.get('name:en', row['name'])
                    
                    # Determine hierarchy based on admin_level
                    hierarchy = self._build_admin_hierarchy(row)
                    boost = self._calculate_boost('admin_boundary', row.get('admin_level'))
                    
                    doc = {
                        '_index': self.es_index,
                        '_id': row['doc_id'],
                        '_source': {
                            'id': row['doc_id'],
                            'entity_type': row['entity_type'],
                            'name': row['name'],
                            'name_ne': row.get('name_ne'),
                            'name_en': name_en,
                            'admin_level': row.get('admin_level'),
                            'location': {
                                'lat': row['lat'],
                                'lon': row['lon']
                            } if row.get('lat') else None,
                            'ward': hierarchy.get('ward'),
                            'municipality': hierarchy.get('municipality'),
                            'municipality_ne': hierarchy.get('municipality_ne'),
                            'district': hierarchy.get('district'),
                            'district_ne': hierarchy.get('district_ne'),
                            'province': hierarchy.get('province'),
                            'province_ne': hierarchy.get('province_ne'),
                            'country': 'Nepal',
                            'boost_score': boost,
                            'search_text': self._build_search_text(row)
                        }
                    }
                    yield doc
                    
            success, failed = helpers.bulk(self.es, generate_docs(), raise_on_error=False)
            logger.info(f"Synced {success} admin boundaries ({failed} failed)")
            return success
            
    def sync_poi(self) -> int:
        """Sync Points of Interest"""
        query = """
        SELECT 
            'poi_' || id::text as doc_id,
            'poi' as entity_type,
            name,
            ST_Y(ST_Transform(geom, 4326)) as lat,
            ST_X(ST_Transform(geom, 4326)) as lon,
            tags
        FROM normalized.poi
        WHERE name IS NOT NULL
        LIMIT 50000  -- Limit POI to top 50k to keep index size reasonable
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            
            def generate_docs():
                for row in cur:
                    # Parse tags from HSTORE string format
                    tags = row.get('tags')
                    if isinstance(tags, str):
                        try:
                            import json
                            tags = json.loads(tags) if tags else {}
                        except:
                            tags = {}
                    elif tags is None:
                        tags = {}
                    name_en = tags.get('name:en', row['name'])
                    
                    doc = {
                        '_index': self.es_index,
                        '_id': row['doc_id'],
                        '_source': {
                            'id': row['doc_id'],
                            'entity_type': row['entity_type'],
                            'name': row['name'],
                            'name_en': name_en,
                            'location': {
                                'lat': row['lat'],
                                'lon': row['lon']
                            } if row.get('lat') else None,
                            'country': 'Nepal',
                            'boost_score': 0.5,  # Lower priority for POI
                            'tags': tags,
                            'search_text': row['name']
                        }
                    }
                    yield doc
                    
            success, failed = helpers.bulk(self.es, generate_docs(), raise_on_error=False)
            logger.info(f"Synced {success} POI ({failed} failed)")
            return success
            
    def sync_roads(self) -> int:
        """Sync named roads"""
        query = """
        SELECT 
            'road_' || id::text as doc_id,
            'road' as entity_type,
            name,
            tags
        FROM normalized.named_roads
        WHERE name IS NOT NULL
        LIMIT 10000  -- Limit roads
        """
        
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query)
            
            def generate_docs():
                for row in cur:
                    # Parse tags from HSTORE string format
                    tags = row.get('tags')
                    if isinstance(tags, str):
                        try:
                            import json
                            tags = json.loads(tags) if tags else {}
                        except:
                            tags = {}
                    elif tags is None:
                        tags = {}
                    name_en = tags.get('name:en', row['name'])
                    
                    doc = {
                        '_index': self.es_index,
                        '_id': row['doc_id'],
                        '_source': {
                            'id': row['doc_id'],
                            'entity_type': row['entity_type'],
                            'name': row['name'],
                            'name_en': name_en,
                            'country': 'Nepal',
                            'boost_score': 0.3,  # Lowest priority
                            'search_text': row['name']
                        }
                    }
                    yield doc
                    
            success, failed = helpers.bulk(self.es, generate_docs(), raise_on_error=False)
            logger.info(f"Synced {success} roads ({failed} failed)")
            return success
            
    def _build_admin_hierarchy(self, row: Dict) -> Dict:
        """Build admin hierarchy for admin boundary entities"""
        admin_level = row.get('admin_level')
        name = row.get('name')
        name_ne = row.get('name_ne')
        centroid = row.get('centroid')
        
        hierarchy = {
            'ward': None,
            'municipality': None,
            'municipality_ne': None,
            'district': None,
            'district_ne': None,
            'province': None,
            'province_ne': None
        }
        
        if admin_level == 4:  # Province
            hierarchy['province'] = name
            hierarchy['province_ne'] = name_ne or name
        elif admin_level == 6:  # District
            hierarchy['district'] = name
            hierarchy['district_ne'] = name_ne or name
            # Find parent province via spatial query
            if centroid:
                parent_hierarchy = self._get_parent_admin(centroid)
                if parent_hierarchy:
                    hierarchy['province'] = parent_hierarchy.get('province')
                    hierarchy['province_ne'] = parent_hierarchy.get('province_ne')
        elif admin_level == 7:  # Municipality
            hierarchy['municipality'] = name
            hierarchy['municipality_ne'] = name_ne or name
            # Find parent district and province via spatial query
            if centroid:
                parent_hierarchy = self._get_parent_admin(centroid)
                if parent_hierarchy:
                    hierarchy['district'] = parent_hierarchy.get('district')
                    hierarchy['district_ne'] = parent_hierarchy.get('district_ne')
                    hierarchy['province'] = parent_hierarchy.get('province')
                    hierarchy['province_ne'] = parent_hierarchy.get('province_ne')
        elif admin_level == 9:  # Ward
            # Extract municipality and ward number from ward name (e.g., "Kathmandu-01")
            import re
            match = re.match(r'^(.+)-(\d+)$', name or '')
            if match:
                hierarchy['municipality'] = match.group(1)
                hierarchy['municipality_ne'] = match.group(1)
                try:
                    hierarchy['ward'] = int(match.group(2))
                except:
                    pass
            
            # Find parent district and province via spatial query
            if centroid:
                parent_hierarchy = self._get_parent_admin(centroid)
                if parent_hierarchy:
                    hierarchy['district'] = parent_hierarchy.get('district')
                    hierarchy['district_ne'] = parent_hierarchy.get('district_ne')
                    hierarchy['province'] = parent_hierarchy.get('province')
                    hierarchy['province_ne'] = parent_hierarchy.get('province_ne')
                
        return hierarchy
    
    def _get_parent_admin(self, centroid: str) -> Optional[Dict]:
        """Find parent district and province for a location using spatial query"""
        try:
            with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
                query = """
                    SELECT 
                        d.name as district,
                        d.name_ne as district_ne,
                        p.name as province,
                        p.name_ne as province_ne
                    FROM normalized.admin_boundaries d
                    CROSS JOIN normalized.admin_boundaries p
                    WHERE d.admin_level = 6 
                      AND p.admin_level = 4
                      AND ST_Contains(d.geom, ST_GeomFromText(%s, 4326))
                      AND ST_Contains(p.geom, ST_GeomFromText(%s, 4326))
                    LIMIT 1
                """
                cur.execute(query, (centroid, centroid))
                result = cur.fetchone()
                return dict(result) if result else None
        except Exception as e:
            logger.warning(f"Failed to get parent admin: {e}")
            return None
        
    def _calculate_boost(self, entity_type: str, subtype: Optional[str] = None) -> float:
        """Calculate search boost score based on entity type"""
        if entity_type == 'place':
            # Prioritize cities, towns over hamlets
            if subtype in ['city', 'town']:
                return 2.0
            elif subtype in ['village', 'suburb']:
                return 1.5
            return 1.0
        elif entity_type == 'admin_boundary':
            # Prioritize districts and municipalities
            if subtype in [6, 7]:  # district, municipality
                return 1.8
            elif subtype == 4:  # province
                return 1.5
            return 1.2
        elif entity_type == 'poi':
            return 0.5
        else:  # roads
            return 0.3
            
    def _build_search_text(self, row: Dict) -> str:
        """Build combined search text for better matching"""
        parts = [
            row.get('name', ''),
            row.get('name_ne', ''),
            row.get('municipality', ''),
            row.get('district', ''),
            row.get('province', '')
        ]
        return ' '.join(filter(None, parts))
        
    def sync_all(self):
        """Sync all entities to Elasticsearch"""
        start_time = datetime.now()
        logger.info("Starting full sync to Elasticsearch...")
        
        try:
            # Connect to database
            self.connect_db()
            
            # Create/recreate index
            self.create_index()
            
            # Sync all entity types
            total_places = self.sync_places()
            total_admin = self.sync_admin_boundaries()
            total_poi = self.sync_poi()
            total_roads = self.sync_roads()
            
            # Summary
            total = total_places + total_admin + total_poi + total_roads
            duration = (datetime.now() - start_time).total_seconds()
            
            logger.info(f"""
=================================================================
SYNC COMPLETED SUCCESSFULLY
=================================================================
Total documents indexed: {total}
  - Places: {total_places}
  - Admin Boundaries: {total_admin}
  - POI: {total_poi}
  - Roads: {total_roads}
  
Duration: {duration:.2f} seconds
Index: {self.es_index}
=================================================================
            """)
            
        except Exception as e:
            logger.error(f"Sync failed: {e}", exc_info=True)
            sys.exit(1)
        finally:
            if self.conn:
                self.conn.close()


if __name__ == '__main__':
    syncer = LocationSyncer()
    syncer.sync_all()
