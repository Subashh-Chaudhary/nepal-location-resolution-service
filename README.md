# Nepal Location Resolution Service

A microservices-based location search system for Nepal.

## Quick Start

```bash
# 1. Add to /etc/hosts
echo "127.0.0.1 search.eshasan.local" | sudo tee -a /etc/hosts

# 2. Start all services
docker-compose up --build

# 3. Test
curl http://search.eshasan.local/graphql
```

## Services

| Service | Port | Description |
|---------|------|-------------|
| Traefik | 80, 8080 | Reverse proxy & dashboard |
| react-widget | - | Embeddable search widget |
| search-core | - | GraphQL API |
| elasticsearch | 9200 | Search engine |
| osm-syncer | - | Periodic data sync |

## Documentation

See [docs/README.md](docs/README.md) for complete documentation.

## License

MIT
