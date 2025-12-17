package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
)

// Response represents the GraphQL-like response structure
type Response struct {
	Data string `json:"data"`
}

// graphqlHandler handles requests to /graphql endpoint
// Currently returns dummy JSON response
func graphqlHandler(w http.ResponseWriter, r *http.Request) {
	log.Printf("[search-core] Received %s request to %s", r.Method, r.URL.Path)

	// Set CORS headers for cross-origin requests
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
	w.Header().Set("Content-Type", "application/json")

	// Handle preflight OPTIONS request
	if r.Method == "OPTIONS" {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Return dummy response
	response := Response{
		Data: "Hello from search-core",
	}

	if err := json.NewEncoder(w).Encode(response); err != nil {
		log.Printf("[search-core] Error encoding response: %v", err)
		http.Error(w, "Internal server error", http.StatusInternalServerError)
		return
	}

	log.Printf("[search-core] Sent dummy response successfully")
}

// healthHandler provides a health check endpoint
func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "healthy"})
}

func main() {
	// Get port from environment or default to 8080
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Register handlers
	http.HandleFunc("/graphql", graphqlHandler)
	http.HandleFunc("/health", healthHandler)

	// Start server
	addr := fmt.Sprintf(":%s", port)
	log.Printf("[search-core] Starting server on %s", addr)
	log.Printf("[search-core] GraphQL endpoint: http://localhost%s/graphql", addr)
	log.Printf("[search-core] Health endpoint: http://localhost%s/health", addr)

	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("[search-core] Server failed to start: %v", err)
	}
}
