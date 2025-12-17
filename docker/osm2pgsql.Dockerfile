FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    osm2pgsql \
    postgresql-client \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /data

ENTRYPOINT ["osm2pgsql"]
