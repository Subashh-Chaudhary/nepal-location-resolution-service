# Python script for Elasticsearch sync
FROM python:3.11-alpine

WORKDIR /app

# Install build dependencies for psycopg2
RUN apk add --no-cache postgresql-dev gcc musl-dev

# Copy requirements and install
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy scripts
COPY sync_to_elasticsearch.py .

# Create mappings directory (mapping will be mounted from volume)
RUN mkdir -p /app/mappings

# Environment variables (override in docker-compose)
ENV POSTGRES_HOST=postgis
ENV POSTGRES_PORT=5432
ENV POSTGRES_DB=nepal_osm
ENV POSTGRES_USER=osm_user
ENV POSTGRES_PASSWORD=osm_secret_password
ENV ELASTICSEARCH_URL=http://elasticsearch:9200
ENV ES_INDEX=nepal_locations

CMD ["python", "sync_to_elasticsearch.py"]
