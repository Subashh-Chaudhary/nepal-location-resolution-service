# Nepal Location Resolution Service - Docker Setup

## Quick Start

### 1. Build and Start All Services

```bash
docker-compose up -d
```

This will start:
- **Traefik** - Reverse proxy on port 80
- **Elasticsearch** - Search engine on port 9200
- **PostGIS** - Spatial database on port 5433
- **search-core** - GraphQL API service
- **react-widget** - Embeddable search widget
- **osm-syncer** - Periodic OSM data synchronizer
- **es-syncer** - One-time PostgreSQL to Elasticsearch sync

### 2. Initialize Database (First Time Only)

```bash
# Import OSM data into PostGIS
docker exec -it postgis psql -U osm_user -d nepal_osm -f /docker-entrypoint-initdb.d/01-init-schema.sql

# Run normalization
docker exec -it postgis psql -U osm_user -d nepal_location_pg -f /path/to/normalize_initial.sql
```

### 3. Sync Data to Elasticsearch

The `es-syncer` service will automatically run once on startup to sync data. To manually trigger sync:

```bash
docker-compose run --rm es-syncer
```

### 4. Access Services

- **GraphQL Playground**: http://localhost/graphql or http://localhost:8080/
- **Elasticsearch**: http://localhost:9200
- **PostGIS**: localhost:5433 (use DBeaver or psql)
- **Traefik Dashboard**: http://localhost:8080

## GraphQL API Usage

### Example Query - Simple Search

```graphql
query {
  searchLocation(input: {
    query: "Kathmandu"
    limit: 10
  }) {
    total
    took
    results {
      id
      entityType
      name
      nameNe
      nameEn
      location {
        lat
        lon
      }
      district
      province
      score
    }
  }
}
```

### Example Query - Search with Parent Validation

```graphql
query {
  searchLocation(input: {
    query: "Nepalgunj"
    district: "Banke"
    province: "Lumbini Province"
    limit: 5
  }) {
    total
    took
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
      province
      score
    }
  }
}
```

### Example Query - Fuzzy Search

```graphql
query {
  searchLocation(input: {
    query: "kathmndu"  # Misspelled
    limit: 10
  }) {
    results {
      name
      nameNe
      district
      score
    }
  }
}
```

## Service Management

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f search-core
docker-compose logs -f es-syncer
docker-compose logs -f elasticsearch
```

### Restart Services

```bash
# Restart all
docker-compose restart

# Restart specific service
docker-compose restart search-core
```

### Rebuild Services

```bash
# Rebuild after code changes
docker-compose build search-core
docker-compose up -d search-core

# Rebuild es-syncer and run
docker-compose build es-syncer
docker-compose run --rm es-syncer
```

### Stop Services

```bash
# Stop all
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

## Troubleshooting

### Elasticsearch Not Starting

Check memory limits:
```bash
docker-compose logs elasticsearch
```

If memory issues, reduce in `docker-compose.yml`:
```yaml
- "ES_JAVA_OPTS=-Xms256m -Xmx256m"
```

### ES Syncer Fails

Check database connection:
```bash
docker exec -it postgis psql -U osm_user -d nepal_location_pg -c "\dt normalized.*"
```

Run sync manually with logs:
```bash
docker-compose run --rm es-syncer python -u sync_to_elasticsearch.py
```

### GraphQL Service Not Responding

Check if Elasticsearch is connected:
```bash
curl http://localhost:8080/health
```

Check logs:
```bash
docker-compose logs search-core
```

### No Search Results

Verify Elasticsearch has data:
```bash
curl http://localhost:9200/nepal_locations/_count
```

Check mapping:
```bash
curl http://localhost:9200/nepal_locations/_mapping
```

## Development Workflow

### Update GraphQL Schema

1. Edit `search-core/schema.graphql`
2. Regenerate code:
   ```bash
   cd search-core
   go run github.com/99designs/gqlgen generate
   ```
3. Rebuild and restart:
   ```bash
   docker-compose build search-core
   docker-compose up -d search-core
   ```

### Update Elasticsearch Mapping

1. Edit `elasticsearch/mappings/nepal_locations.json`
2. Rebuild es-syncer:
   ```bash
   docker-compose build es-syncer
   ```
3. Delete index and resync:
   ```bash
   curl -X DELETE http://localhost:9200/nepal_locations
   docker-compose run --rm es-syncer
   ```

### Update Sync Logic

1. Edit `scripts/sync_to_elasticsearch.py`
2. Rebuild and run:
   ```bash
   docker-compose build es-syncer
   docker-compose run --rm es-syncer
   ```

## Architecture

```
User Request
    ↓
Traefik (Port 80)
    ↓
search-core (GraphQL API)
    ↓
Elasticsearch (Search Index)
    ↑
es-syncer (One-time sync)
    ↑
PostGIS (Normalized Data)
    ↑
osm-syncer (Periodic OSM updates)
```

## Performance Tuning

### Elasticsearch

- Increase heap size for large datasets in `docker-compose.yml`
- Adjust `number_of_shards` in mapping for distributed setup
- Add replicas for high availability

### Search Query

- Use `limit` parameter to control result size
- Leverage boost_score for relevance ranking
- Use parent filters to narrow search scope

### Database

- Ensure spatial indexes exist on geometry columns
- Monitor query performance with EXPLAIN ANALYZE
- Consider connection pooling for high traffic

## Security Notes

⚠️ **Current configuration is for development only**

For production:
1. Enable Elasticsearch security (xpack.security.enabled=true)
2. Add authentication to GraphQL endpoint
3. Use environment files for secrets (not committed to git)
4. Enable HTTPS on Traefik
5. Restrict network access
6. Use read-only database user for syncer
