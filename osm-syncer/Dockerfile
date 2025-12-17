# OSM Syncer - Go service
FROM golang:1.21-alpine AS builder

WORKDIR /app

# Copy go mod file
COPY go.mod ./

# Copy source code
COPY main.go ./

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o osm-syncer .

# Final stage - minimal image
FROM alpine:latest

WORKDIR /app

# Copy binary from builder
COPY --from=builder /app/osm-syncer .

# Run the service
CMD ["./osm-syncer"]
