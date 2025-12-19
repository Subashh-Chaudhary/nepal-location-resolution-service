package graph

import (
	elasticsearch "github.com/elastic/go-elasticsearch/v8"
)

type Resolver struct {
	ESClient *elasticsearch.Client
}

// Query returns QueryResolver implementation.
func (r *Resolver) Query() QueryResolver { return &queryResolver{r} }

type queryResolver struct{ *Resolver }
