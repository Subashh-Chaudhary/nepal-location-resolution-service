# Nepal Location Resolution Service

A microservices-based location search system for Nepal, built with Docker Compose.

## 🏗️ Architecture Overview

```
                                    ┌─────────────────────────────────────────┐
                                    │           search.eshasan.local          │
                                    └─────────────────────────────────────────┘
                                                        │
                                                        ▼
                                    ┌─────────────────────────────────────────┐
                                    │              TRAEFIK                     │
                                    │         (Reverse Proxy)                  │
                                    │                                          │
                                    │  /widget.js → react-widget              │
                                    │  /graphql   → search-core               │
                                    └─────────────────────────────────────────┘
                                           │                    │
                           ┌───────────────┘                    └───────────────┐
                           ▼                                                    ▼
              ┌─────────────────────────┐                      ┌─────────────────────────┐
              │     REACT WIDGET        │                      │      SEARCH-CORE        │
              │   (Nginx + React)       │                      │     (Go + GraphQL)      │
              │                         │                      │                         │
              │ Embeddable search       │                      │ /graphql endpoint       │
              │ component               │                      │ Returns dummy JSON      │
              └─────────────────────────┘                      └─────────────────────────┘
                                                                          │
                                                                          ▼
                                                              ┌─────────────────────────┐
                                                              │     ELASTICSEARCH       │
                                                              │    (Search Engine)      │
                                                              │                         │
                                                              │ Single-node cluster     │
                                                              │ Stores location data    │
                                                              └─────────────────────────┘
                                                                          ▲
                                                                          │
                                                              ┌─────────────────────────┐
                                                              │      OSM-SYNCER         │
                                                              │   (Periodic Sync)       │
                                                              │                         │
                                                              │ Runs every 5 minutes    │
                                                              │ Logs dummy sync         │
                                                              └─────────────────────────┘
```

## 📁 Project Structure

```
nepal-location-resolution-service/
├── docker-compose.yml          # Main orchestration file
├── .env                        # Global environment variables
│
├── traefik/                    # Reverse proxy configuration
│   ├── traefik.yml            # Static configuration (entrypoints, providers)
│   └── dynamic.yml            # Dynamic configuration (routes, services)
│
├── react-widget/              # Embeddable search widget
│   ├── package.json           # NPM dependencies
│   ├── webpack.config.js      # Build configuration
│   ├── nginx.conf             # Nginx server configuration
│   ├── Dockerfile             # Multi-stage build (Node → Nginx)
│   ├── .env                   # Widget environment variables
│   └── src/
│       └── index.js           # React widget source code
│
├── search-core/               # GraphQL API service
│   ├── main.go                # Go HTTP server
│   ├── go.mod                 # Go module definition
│   ├── Dockerfile             # Multi-stage build
│   └── .env                   # Service environment variables
│
├── osm-syncer/                # Periodic data synchronizer
│   ├── main.go                # Go sync service
│   ├── go.mod                 # Go module definition
│   ├── Dockerfile             # Multi-stage build
│   └── .env                   # Service environment variables
│
└── docs/
    └── README.md              # This documentation
```

## 🛠️ Tech Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Routing** | Traefik v2.10 | Reverse proxy, load balancing, request routing |
| **Frontend** | React 18 + Webpack 5 | Embeddable search widget |
| **Backend** | Go 1.21 | Search API and sync services |
| **Search** | Elasticsearch 8.11 | Full-text search engine |
| **Containers** | Docker + Docker Compose | Container orchestration |
| **Web Server** | Nginx | Serving static React bundle |

## 🚀 Quick Start

### Prerequisites

- Docker Engine (20.10+)
- Docker Compose (v2.0+)
- Text editor for `/etc/hosts` modification

### Step 1: Configure Local DNS

Add the following entry to your `/etc/hosts` file:

```bash
# Linux/macOS
sudo nano /etc/hosts

# Add this line:
127.0.0.1 search.eshasan.local
```

On Windows, edit `C:\Windows\System32\drivers\etc\hosts` as Administrator.

### Step 2: Start All Services

```bash
# Navigate to project root
cd nepal-location-resolution-service

# Build and start all services
docker-compose up --build

# Or run in detached mode
docker-compose up --build -d
```

### Step 3: Verify Services

Once all services are running, verify each component:

| Service | URL | Expected Result |
|---------|-----|-----------------|
| **Traefik Dashboard** | http://localhost:8080 | Traefik admin UI |
| **Widget** | http://search.eshasan.local/widget.js | JavaScript bundle |
| **Test Page** | http://search.eshasan.local | Widget test page |
| **GraphQL** | http://search.eshasan.local/graphql | `{"data":"Hello from search-core"}` |
| **Elasticsearch** | http://localhost:9200 | Cluster health JSON |

### Step 4: Check Logs

```bash
# View all logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f osm-syncer
docker-compose logs -f search-core
```

## 📖 Service Details

### Traefik (Reverse Proxy)

**Purpose:** Single entrypoint for all HTTP requests. Routes traffic to appropriate services based on URL path.

**Configuration Files:**
- `traefik/traefik.yml` - Static config (ports, providers)
- `traefik/dynamic.yml` - Routing rules

**Routing Rules:**
- `Host(search.eshasan.local) && PathPrefix(/widget.js)` → react-widget
- `Host(search.eshasan.local) && PathPrefix(/graphql)` → search-core
- Default → react-widget (for testing)

**Ports:**
- `80` - HTTP traffic
- `8080` - Dashboard

---

### React Widget

**Purpose:** Embeddable search component that can be included in any webpage.

**Features:**
- Compiled via Webpack to single `widget.js` bundle
- Served via Nginx
- Auto-mounts to DOM when loaded
- Currently logs search input to console (dummy implementation)

**Embedding:**
```html
<script src="http://search.eshasan.local/widget.js"></script>
```

Or with a specific container:
```html
<div id="nepal-location-widget"></div>
<script src="http://search.eshasan.local/widget.js"></script>
```

**Build Process:**
1. Node.js builds React app with Webpack
2. Output: `dist/widget.js`
3. Nginx serves the static bundle

---

### Search-Core (Go API)

**Purpose:** Backend GraphQL API service for location search.

**Endpoints:**
- `GET/POST /graphql` - GraphQL endpoint (returns dummy JSON)
- `GET /health` - Health check

**Current Response:**
```json
{"data": "Hello from search-core"}
```

**Future Development:**
- Real GraphQL schema
- Elasticsearch integration
- Location search queries

---

### Elasticsearch

**Purpose:** Full-text search engine for storing and querying Nepal location data.

**Configuration:**
- Single-node cluster
- Security disabled (development only)
- 512MB heap size
- Persistent volume for data

**Access:**
```bash
# Check cluster health
curl http://localhost:9200/_cluster/health

# Create dummy index
curl -X PUT http://localhost:9200/nepal-locations
```

---

### OSM-Syncer

**Purpose:** Periodic background service that syncs OpenStreetMap data to Elasticsearch.

**Current Behavior:**
- Runs every 5 minutes (configurable via `SYNC_INTERVAL_MINUTES`)
- Logs "dummy sync executed"
- Waits for Elasticsearch to be healthy before starting

**Future Development:**
- Download Nepal OSM data
- Parse and transform locations
- Index to Elasticsearch

## 🔧 Configuration

### Environment Variables

All services use `.env` files for configuration:

| Service | File | Key Variables |
|---------|------|---------------|
| Global | `.env` | `DOMAIN`, `NODE_ENV` |
| react-widget | `react-widget/.env` | `REACT_APP_API_URL` |
| search-core | `search-core/.env` | `PORT`, `ELASTICSEARCH_URL` |
| osm-syncer | `osm-syncer/.env` | `SYNC_INTERVAL_MINUTES`, `ELASTICSEARCH_URL` |

### Customizing Sync Interval

Edit `osm-syncer/.env`:
```bash
SYNC_INTERVAL_MINUTES=1  # Sync every minute
```

Then restart:
```bash
docker-compose restart osm-syncer
```

## 🧪 Testing

### Test Widget Embedding

Create a test HTML file:
```html
<!DOCTYPE html>
<html>
<head>
    <title>Widget Test</title>
</head>
<body>
    <h1>My Website</h1>
    <p>Below is the embedded Nepal location search:</p>
    <script src="http://search.eshasan.local/widget.js"></script>
</body>
</html>
```

Open in browser and check:
1. Widget renders correctly
2. Search input works
3. Console shows search queries

### Test GraphQL Endpoint

```bash
# GET request
curl http://search.eshasan.local/graphql

# POST request
curl -X POST http://search.eshasan.local/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "test"}'
```

### Test Elasticsearch

```bash
# Cluster health
curl http://localhost:9200/_cluster/health?pretty

# Create index
curl -X PUT http://localhost:9200/nepal-locations

# List indices
curl http://localhost:9200/_cat/indices
```

## 📊 Monitoring

### View Service Status

```bash
docker-compose ps
```

### Resource Usage

```bash
docker stats
```

### Traefik Dashboard

Open http://localhost:8080 to see:
- Registered routers
- Service health
- Request metrics

## 🛑 Stopping Services

```bash
# Stop all services
docker-compose down

# Stop and remove volumes (clears Elasticsearch data)
docker-compose down -v

# Stop specific service
docker-compose stop osm-syncer
```

## 🔄 Development Workflow

### Rebuilding a Single Service

```bash
# Rebuild and restart react-widget
docker-compose up --build -d react-widget

# Rebuild search-core
docker-compose up --build -d search-core
```

### Viewing Real-time Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f search-core
```

### Accessing Container Shell

```bash
# Elasticsearch
docker exec -it elasticsearch /bin/bash

# Search-core
docker exec -it search-core /bin/sh
```

## 🚧 Future Development

This is a bare-minimum infrastructure setup. Future enhancements include:

1. **Real GraphQL Schema** - Define types for locations, districts, municipalities
2. **OSM Data Ingestion** - Download and parse Nepal OSM data
3. **Elasticsearch Mapping** - Proper index mapping for geo-search
4. **Widget API Integration** - Connect widget to /graphql endpoint
5. **Authentication** - Add API key authentication
6. **HTTPS** - Configure TLS certificates via Traefik
7. **Production Config** - Multi-node Elasticsearch, replicas, etc.

## 📝 License

MIT License - See LICENSE file for details.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make changes
4. Submit a pull request

---

**Built for Nepal 🇳🇵**
