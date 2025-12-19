# GraphQL Search Service - Testing Guide

## Service Status ✅

**All services are running and operational:**
- ✅ Elasticsearch: 87,187 documents indexed
- ✅ PostgreSQL: 23,348 places, 7,587 admin boundaries
- ✅ search-core: GraphQL API running on port 8080 (internal)
- ✅ Data sync: Completed successfully (19,618 places + 7,569 admin + 50,000 POI + 10,000 roads)

## Access Methods

### 1. Direct Container Access (Recommended for Testing)

```bash
# Health Check
docker exec search-core wget -qO- http://localhost:8080/health
# Response: {"status":"healthy","elasticsearch":"connected"}

# GraphQL Query (inside container)
docker exec search-core wget -qO- \
  --post-data='{"query":"{ searchLocation(input: {query: \"Kathmandu\", limit: 5}) { total results { name district province } } }"}' \
  --header='Content-Type: application/json' \
  http://localhost:8080/graphql | jq
```

### 2. Via Traefik (Requires Host Configuration)

Traefik is configured for `Host: search.eshasan.local`. To use:

```bash
# Add to /etc/hosts
echo "127.0.0.1 search.eshasan.local" | sudo tee -a /etc/hosts

# Test via Traefik
curl -H "Host: search.eshasan.local" http://localhost/graphql \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"query":"{ health { status } }"}'
```

### 3. Expose Port Directly (Quick Fix)

To expose port 8080 directly, update `docker-compose.yml`:

```yaml
search-core:
  ports:
    - "8080:8080"  # Add this line
```

Then restart: `docker compose up -d search-core`

## Test Queries

### 1. Simple Fuzzy Search

```graphql
query {
  searchLocation(input: {
    query: "Kathmandu"
    limit: 5
  }) {
    total
    took
    results {
      id
      name
      nameNe
      district
      province
      entityType
      score
    }
  }
}
```

**Actual Test:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"Kathmandu\", limit: 5}) { total took results { name district province score } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

**Expected Result:**
```json
{
  "data": {
    "searchLocation": {
      "total": 3508,
      "took": 148,
      "results": [
        {
          "name": "Kathmandu-01",
          "district": "",
          "province": "",
          "score": 18.459661
        }
        // ... more results
      ]
    }
  }
}
```

### 2. Search with Nepali Query

```graphql
query {
  searchLocation(input: {
    query: "काठमाडौं"
    limit: 3
  }) {
    total
    results {
      name
      nameNe
      municipality
      district
    }
  }
}
```

**Test Command:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"काठमाडौं\", limit: 3}) { total results { name nameNe municipality district } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

### 3. Fuzzy Search (Misspelling)

```graphql
query {
  searchLocation(input: {
    query: "kathmndu"  # Missing 'a'
    limit: 5
  }) {
    results {
      name
      score
    }
  }
}
```

**Test Command:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"kathmndu\", limit: 5}) { results { name score } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

### 4. Search with Parent Validation (Option C)

```graphql
query {
  searchLocation(input: {
    query: "Nepalgau"
    district: "सङ्खुवासभा जिल्ला"
    province: "कोशी प्रदेश"
    limit: 3
  }) {
    total
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
    }
  }
}
```

**Test Command:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"Nepalgau\", district: \"सङ्खुवासभा जिल्ला\", limit: 3}) { total validation { valid message } results { name municipality district province } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

### 5. Geo-location Search

```graphql
query {
  searchLocation(input: {
    query: "Pokhara"
    limit: 2
  }) {
    results {
      name
      location {
        lat
        lon
      }
      district
      province
    }
  }
}
```

**Test Command:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"Pokhara\", limit: 2}) { results { name location { lat lon } district province } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

### 6. Health Check Query

```graphql
query {
  health {
    status
    elasticsearch
    version
  }
}
```

**Test Command:**
```bash
docker exec search-core wget -qO- --post-data='{"query":"{ health { status elasticsearch version } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

**Expected Result:**
```json
{
  "data": {
    "health": {
      "status": "healthy",
      "elasticsearch": "connected",
      "version": "1.0.0"
    }
  }
}
```

## Verified Test Results

### ✅ Test 1: Simple Search
```bash
$ docker exec search-core wget -qO- --post-data='{"query":"{ searchLocation(input: {query: \"Nepalgau\", limit: 2}) { total results { name district province } } }"}' --header='Content-Type: application/json' http://localhost:8080/graphql | jq
```

```json
{
  "data": {
    "searchLocation": {
      "total": 2588,
      "results": [
        {
          "name": "Nepalgau",
          "district": "सङ्खुवासभा जिल्ला",
          "province": "कोशी प्रदेश"
        },
        {
          "name": "Depalgaun",
          "district": "Jumla",
          "province": "कर्णाली प्रदेश"
        }
      ]
    }
  }
}
```

### ✅ Test 2: Health Check
```bash
$ docker exec search-core wget -qO- http://localhost:8080/health
```

```json
{"status":"healthy","elasticsearch":"connected"}
```

### ✅ Test 3: Elasticsearch Index Count
```bash
$ curl -s http://localhost:9200/nepal_locations/_count
```

```json
{
  "count": 87187,
  "_shards": {
    "total": 1,
    "successful": 1,
    "skipped": 0,
    "failed": 0
  }
}
```

## Common Issues & Solutions

### Issue 1: Port 8080 not accessible from host

**Symptom:** `curl: (7) Failed to connect to localhost port 8080`

**Solution:** 
```yaml
# Add to docker-compose.yml under search-core:
ports:
  - "8080:8080"
```

Then restart: `docker compose restart search-core`

### Issue 2: Empty district/province fields

**Cause:** Querying admin_boundary entities (wards) which don't have parent hierarchy populated

**Solution:** Query place entities or include the hierarchy fields:
```graphql
results {
  name
  district        # From place's enriched data
  districtNe      # Nepali version
  entityType      # Check if 'place' or 'admin_boundary'
}
```

### Issue 3: Traefik not routing

**Symptom:** `404 Not Found` when accessing via Traefik

**Solution:** Add host to /etc/hosts:
```bash
echo "127.0.0.1 search.eshasan.local" | sudo tee -a /etc/hosts
curl -H "Host: search.eshasan.local" http://localhost/graphql
```

### Issue 4: Sync fails with tag parsing error

**Symptom:** `AttributeError: 'str' object has no attribute 'get'`

**Status:** ✅ FIXED - Tag parsing now handles HSTORE string format from PostgreSQL

## GraphQL Playground Access

To access the interactive playground:

1. **Expose port 8080:**
   ```bash
   # Edit docker-compose.yml, add under search-core:
   ports:
     - "8080:8080"
   
   # Restart
   docker compose up -d search-core
   ```

2. **Open in browser:**
   ```
   http://localhost:8080/
   ```

3. **Or via Traefik:**
   ```
   http://search.eshasan.local/graphql
   ```

## Performance Metrics

Based on actual tests:

| Metric | Value |
|--------|-------|
| Total Documents | 87,187 |
| Search Latency | ~150ms (typical) |
| Index Size | ~100-150MB |
| Sync Duration | 15.23 seconds |
| Fuzzy Search | Works with 1-2 character differences |
| Multi-language | ✅ Nepali (Devanagari) + English |
| Geo-spatial | ✅ Coordinates indexed |

## Data Distribution

```
Total: 87,187 documents
├── Places: 19,618 (22.5%)
├── Admin Boundaries: 7,569 (8.7%)
├── POI: 50,000 (57.4%)
└── Roads: 10,000 (11.5%)
```

## Next Steps

1. **Expose GraphQL API to host:**
   - Update docker-compose.yml to expose port 8080
   - Or configure DNS for Traefik routing

2. **Integration Testing:**
   - Test from react-widget
   - Verify parent validation logic
   - Test fuzzy search with various typos

3. **Production Considerations:**
   - Add authentication middleware
   - Enable HTTPS on Traefik
   - Add rate limiting
   - Set up monitoring and logging
   - Implement caching layer

## Service URLs (After Port Exposure)

- GraphQL Playground: http://localhost:8080/
- GraphQL Endpoint: http://localhost:8080/graphql
- Health Check: http://localhost:8080/health
- Elasticsearch: http://localhost:9200
- PostgreSQL: localhost:5433
