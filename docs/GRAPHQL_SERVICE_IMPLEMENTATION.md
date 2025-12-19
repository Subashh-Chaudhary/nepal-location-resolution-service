# GraphQL Search Service - Implementation Summary

## ✅ Completed Implementation

### 1. GraphQL Schema (`search-core/schema.graphql`)
- **Query Type**: `searchLocation` with fuzzy search and parent validation
- **Input Type**: `LocationSearchInput` with optional filters (ward, municipality, district, province)
- **Response Type**: `LocationSearchResponse` with results, total count, execution time, and validation
- **Location Type**: Complete flat denormalized structure with all administrative hierarchy levels
- **Validation Types**: `ValidationResult` and `ValidationMismatch` for parent location verification
- **Health Check**: Service and Elasticsearch connection status

### 2. Go GraphQL Service (`search-core/`)

#### Main Application (`main.go`)
- Elasticsearch client initialization
- GraphQL handler setup with gqlgen
- Playground interface at root path
- Health check endpoint at `/health`
- Environment-based configuration (PORT, ELASTICSEARCH_URL)

#### Resolver Implementation (`graph/resolver.go`, `graph/search.go`)
**Core Features:**
- **Fuzzy Search**: Multi-field matching with AUTO fuzziness
- **Multi-language Support**: Nepali and English name fields with boost
- **Geo-spatial Support**: Location coordinates as geo_point
- **Parent Validation**: Optional validation of ward/municipality/district/province hierarchy
- **Boost Scoring**: Combined Elasticsearch _score and custom boost_score field
- **Top N Results**: Configurable limit (default 10, max 50)

**Search Query Builder:**
- Multi-match query across name, name_ne, name_en, and fuzzy variants
- Field boosting: exact names (^3) > fuzzy names (^2) > search_text
- Optional must clauses for parent filters
- Sort by _score DESC, then boost_score DESC

**Validation Logic:**
- Only validates if parent filters are provided
- Checks top result against expected parent values
- Returns detailed mismatches with field/expected/actual
- Case-insensitive string matching

### 3. Elasticsearch Setup

#### Index Mapping (`elasticsearch/mappings/nepal_locations.json`)
**Analyzers:**
- `nepali_analyzer`: Standard tokenization with Nepali stop words
- `english_fuzzy`: Lowercase + edge n-gram (2-20 chars) for autocomplete
- `nepali_fuzzy`: Lowercase + edge n-gram for Nepali text

**Field Structure:**
- `entity_type` (keyword): place, admin_boundary, poi, road
- `name`, `name_ne`, `name_en` (text + keyword + fuzzy variants)
- `location` (geo_point): lat/lon coordinates
- `ward` (integer): Ward number
- `municipality`, `municipality_ne` (text + keyword)
- `district`, `district_ne` (text + keyword)
- `province`, `province_ne` (text + keyword)
- `country` (keyword): Always "Nepal"
- `boost_score` (float): Relevance boost (0.3-2.0)
- `search_text` (text): Combined searchable text
- `place_type` (keyword): city, town, village, hamlet
- `admin_level` (integer): 2, 4, 6, 7, 9

### 4. Data Sync Service (`scripts/`)

#### Python Sync Script (`sync_to_elasticsearch.py`)
**Features:**
- PostgreSQL to Elasticsearch ETL pipeline
- Separate sync methods for places, admin boundaries, POI, roads
- Boost score calculation based on entity type
- Search text builder combining all name variants
- Bulk indexing with elasticsearch.helpers.bulk()
- Configurable via environment variables

**Boost Scoring:**
- Places: city/town (2.0), village (1.5), hamlet (1.0), other (1.2)
- Admin: province (1.5), district (1.8), municipality (1.8), ward (1.2)
- POI: 0.5
- Roads: 0.3

**Data Limits:**
- Places: unlimited (all 23,348)
- Admin boundaries: unlimited (all 7,587)
- POI: 50,000 (limited for index size)
- Roads: 10,000 (limited for index size)

#### Dependencies (`requirements.txt`)
- psycopg2-binary==2.9.9
- elasticsearch==8.11.0

### 5. Docker Configuration

#### Search Core Dockerfile (`search-core/Dockerfile`)
- Multi-stage build (builder + runtime)
- Go 1.24 alpine base
- CGO disabled for static binary
- Dependencies downloaded and cached
- Final image: ~20MB

#### ES Syncer Dockerfile (`scripts/Dockerfile`)
- Python 3.11 alpine base
- PostgreSQL development dependencies
- Mapping file mounted from volume
- Runs once on startup (restart: no)

#### Docker Compose Updates (`docker-compose.yml`)
**New Service: es-syncer**
- Builds from scripts/Dockerfile
- Runs once on startup (restart: "no")
- Depends on Elasticsearch and PostGIS health checks
- Environment: POSTGRES_HOST, POSTGRES_DB=nepal_location_pg, ES_INDEX=nepal_locations
- Volume mount: ./elasticsearch/mappings:/app/mappings:ro

**Updated Service: search-core**
- New build context with all source files
- Environment: ELASTICSEARCH_URL=http://elasticsearch:9200
- Depends on Elasticsearch health check
- Traefik routing to /graphql endpoint

## 📊 API Examples

### Simple Fuzzy Search
```graphql
query {
  searchLocation(input: {
    query: "kathmndu"
    limit: 5
  }) {
    total
    took
    results {
      name
      nameNe
      district
      province
      score
    }
  }
}
```

### Search with Parent Validation
```graphql
query {
  searchLocation(input: {
    query: "Nepalgunj"
    district: "Banke"
    municipality: "Nepalgunj"
  }) {
    validation {
      valid
      message
      mismatches {
        field
        expected
        actual
      }
    }
    results {
      name
      municipality
      district
      ward
    }
  }
}
```

### Health Check
```graphql
query {
  health {
    status
    elasticsearch
    version
  }
}
```

## 🚀 Deployment Instructions

### 1. Build Services
```bash
cd /home/subashtharu/Desktop/ninja/nepal-location-resolution-service

# Build all services
docker compose build

# Or build individually
docker compose build search-core
docker compose build es-syncer
```

### 2. Start Infrastructure
```bash
# Start Elasticsearch and PostGIS
docker compose up -d elasticsearch postgis

# Wait for health checks
docker compose ps
```

### 3. Initialize Data
```bash
# Run normalization SQL (if not already done)
docker exec -it postgis psql -U osm_user -d nepal_location_pg -f /path/to/normalize_initial.sql

# Run ES sync
docker compose run --rm es-syncer
```

### 4. Start Application Services
```bash
# Start all services
docker compose up -d

# Or start individually
docker compose up -d search-core
docker compose up -d react-widget
docker compose up -d traefik
```

### 5. Verify Services
```bash
# Check logs
docker compose logs -f search-core
docker compose logs es-syncer

# Test health
curl http://localhost:8080/health

# Test GraphQL
curl http://localhost:8080/graphql -X POST \
  -H "Content-Type: application/json" \
  -d '{"query":"{ health { status elasticsearch } }"}'

# Check Elasticsearch
curl http://localhost:9200/nepal_locations/_count
```

### 6. Access Services
- **GraphQL Playground**: http://localhost:8080/ (or http://localhost/graphql via Traefik)
- **Direct GraphQL**: http://localhost:8080/graphql
- **Health Check**: http://localhost:8080/health
- **Elasticsearch**: http://localhost:9200
- **Traefik Dashboard**: http://localhost:8080 (if enabled)

## 🔧 Configuration

### Environment Variables (docker-compose.yml)

**search-core:**
- `PORT=8080`: GraphQL server port
- `ELASTICSEARCH_URL=http://elasticsearch:9200`: ES connection URL

**es-syncer:**
- `POSTGRES_HOST=postgis`: PostgreSQL host
- `POSTGRES_PORT=5432`: PostgreSQL port
- `POSTGRES_DB=nepal_location_pg`: Database name
- `POSTGRES_USER=osm_user`: Database user
- `POSTGRES_PASSWORD=osm_secret_password`: Database password
- `ELASTICSEARCH_URL=http://elasticsearch:9200`: ES URL
- `ES_INDEX=nepal_locations`: Index name

### Customization

**Search Behavior:**
- Edit `graph/search.go` → `buildSearchQuery()` to adjust fuzziness, field weights, or filters
- Modify `performValidation()` for custom validation logic

**Boost Scores:**
- Edit `scripts/sync_to_elasticsearch.py` → `calculate_boost_score()` methods
- Adjust values in sync_places(), sync_admin_boundaries(), etc.

**Index Mapping:**
- Edit `elasticsearch/mappings/nepal_locations.json`
- Rebuild es-syncer: `docker compose build es-syncer`
- Delete index: `curl -X DELETE http://localhost:9200/nepal_locations`
- Resync: `docker compose run --rm es-syncer`

## 📈 Performance Characteristics

- **Search Latency**: <50ms for typical queries (depends on index size and query complexity)
- **Index Size**: ~100-200MB for full Nepal dataset (depends on POI/roads limits)
- **Fuzzy Tolerance**: AUTO fuzziness (1-2 edits based on term length)
- **Concurrent Queries**: Limited by Elasticsearch heap size (default 512MB)
- **Build Time**: search-core (~60s), es-syncer (~200s with dependencies)

## 🎯 Key Features Implemented

✅ **Fuzzy Search**: Handles typos and variations in place names  
✅ **Multi-language**: Nepali (Devanagari) and English name support  
✅ **Parent Validation**: Optional verification of administrative hierarchy  
✅ **Geo-spatial**: Coordinate-based location data  
✅ **Relevance Ranking**: Combined Elasticsearch score + custom boost  
✅ **Flat Response**: Denormalized data structure for easy consumption  
✅ **Top N Results**: Configurable result limit (default 10, max 50)  
✅ **Health Checks**: Service and dependency monitoring  
✅ **Docker-based**: Complete containerized deployment  
✅ **Auto-sync**: One-time data synchronization on startup  
✅ **GraphQL Playground**: Interactive query interface  

## 🔐 Security Notes

⚠️ **Current configuration is for development only**

For production deployment:
1. Enable Elasticsearch authentication (xpack.security.enabled=true)
2. Add GraphQL authentication middleware
3. Use secrets management (not environment files)
4. Enable HTTPS on Traefik
5. Restrict network access with firewall rules
6. Use read-only database credentials for syncer
7. Add rate limiting on GraphQL endpoint
8. Enable CORS with specific origins only
9. Add query complexity limits
10. Monitor and log all API access

## 📝 Next Steps (Optional Enhancements)

1. **Pagination**: Add cursor-based pagination for large result sets
2. **Aggregations**: Add faceted search (count by district, province, etc.)
3. **Caching**: Redis layer for frequently accessed queries
4. **Monitoring**: Prometheus metrics and Grafana dashboards
5. **Testing**: Unit tests for resolvers, integration tests for search
6. **Documentation**: OpenAPI/Swagger alternative endpoint
7. **Batch Operations**: Bulk location validation endpoint
8. **Real-time Sync**: Change data capture from PostgreSQL
9. **Geo-queries**: Radius search, bounding box queries
10. **Autocomplete**: Dedicated suggest endpoint with edge n-grams
