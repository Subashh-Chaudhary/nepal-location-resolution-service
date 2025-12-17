package main

import (
	"log"
	"os"
	"strconv"
	"time"
)

// getEnvInt retrieves an integer environment variable or returns a default
func getEnvInt(key string, defaultVal int) int {
	if val := os.Getenv(key); val != "" {
		if intVal, err := strconv.Atoi(val); err == nil {
			return intVal
		}
	}
	return defaultVal
}

// dummySync simulates an OSM data synchronization
// In the future, this would:
// - Fetch OSM data for Nepal
// - Parse and transform the data
// - Index into Elasticsearch
func dummySync() {
	log.Println("[osm-syncer] ========================================")
	log.Println("[osm-syncer] Starting dummy sync execution...")
	log.Println("[osm-syncer] Simulating OSM data fetch for Nepal...")

	// Simulate some work
	time.Sleep(2 * time.Second)

	log.Println("[osm-syncer] Simulating data transformation...")
	time.Sleep(1 * time.Second)

	log.Println("[osm-syncer] Simulating Elasticsearch indexing...")
	time.Sleep(1 * time.Second)

	log.Println("[osm-syncer] dummy sync executed")
	log.Println("[osm-syncer] ========================================")
}

func main() {
	// Get sync interval from environment (default: 5 minutes)
	syncIntervalMinutes := getEnvInt("SYNC_INTERVAL_MINUTES", 5)
	syncInterval := time.Duration(syncIntervalMinutes) * time.Minute

	log.Printf("[osm-syncer] Starting OSM Syncer service")
	log.Printf("[osm-syncer] Sync interval: %v", syncInterval)
	log.Printf("[osm-syncer] Elasticsearch URL: %s", os.Getenv("ELASTICSEARCH_URL"))

	// Run initial sync immediately
	log.Println("[osm-syncer] Running initial sync...")
	dummySync()

	// Create ticker for periodic syncs
	ticker := time.NewTicker(syncInterval)
	defer ticker.Stop()

	log.Printf("[osm-syncer] Waiting for next sync in %v...", syncInterval)

	// Run periodic syncs
	for range ticker.C {
		dummySync()
		log.Printf("[osm-syncer] Waiting for next sync in %v...", syncInterval)
	}
}
