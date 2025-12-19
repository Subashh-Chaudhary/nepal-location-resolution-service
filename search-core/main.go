package main

import (
	"log"
	"net/http"
	"os"

	"github.com/99designs/gqlgen/graphql/handler"
	"github.com/99designs/gqlgen/graphql/playground"
	elasticsearch "github.com/elastic/go-elasticsearch/v8"

	"search-core/graph"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	esURL := os.Getenv("ELASTICSEARCH_URL")
	if esURL == "" {
		esURL = "http://localhost:9200"
	}

	// Initialize Elasticsearch client
	cfg := elasticsearch.Config{
		Addresses: []string{esURL},
	}
	esClient, err := elasticsearch.NewClient(cfg)
	if err != nil {
		log.Fatalf("Error creating Elasticsearch client: %v", err)
	}

	// Test Elasticsearch connection
	res, err := esClient.Info()
	if err != nil {
		log.Fatalf("Error getting Elasticsearch info: %v", err)
	}
	res.Body.Close()
	log.Printf("Connected to Elasticsearch at %s", esURL)

	// Create resolver with Elasticsearch client
	resolver := &graph.Resolver{
		ESClient: esClient,
	}

	// Create GraphQL server
	srv := handler.NewDefaultServer(graph.NewExecutableSchema(graph.Config{Resolvers: resolver}))

	// Register handlers
	http.Handle("/", playground.Handler("GraphQL playground", "/graphql"))
	http.Handle("/graphql", srv)
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"healthy","elasticsearch":"connected"}`))
	})

	log.Printf("Server starting on :%s", port)
	log.Printf("GraphQL endpoint: http://localhost:%s/graphql", port)
	log.Printf("GraphQL playground: http://localhost:%s/", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
