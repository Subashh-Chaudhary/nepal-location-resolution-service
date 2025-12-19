package graph

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	"search-core/graph/model"
)

// SearchLocations performs fuzzy search with optional parent validation
func (r *queryResolver) SearchLocation(ctx context.Context, input model.LocationSearchInput) (*model.LocationSearchResponse, error) {
	// Set default limit
	limit := 10
	if input.Limit != nil && *input.Limit > 0 {
		limit = *input.Limit
		if limit > 50 {
			limit = 50
		}
	}

	// Build Elasticsearch query
	query := buildSearchQuery(input, limit)

	// Execute search
	var buf bytes.Buffer
	if err := json.NewEncoder(&buf).Encode(query); err != nil {
		return nil, fmt.Errorf("error encoding query: %w", err)
	}

	res, err := r.ESClient.Search(
		r.ESClient.Search.WithContext(ctx),
		r.ESClient.Search.WithIndex("nepal_locations"),
		r.ESClient.Search.WithBody(&buf),
		r.ESClient.Search.WithTrackTotalHits(true),
	)
	if err != nil {
		return nil, fmt.Errorf("error executing search: %w", err)
	}
	defer res.Body.Close()

	if res.IsError() {
		body, _ := io.ReadAll(res.Body)
		return nil, fmt.Errorf("elasticsearch error: %s - %s", res.Status(), string(body))
	}

	// Parse response
	var esResponse ElasticsearchResponse
	if err := json.NewDecoder(res.Body).Decode(&esResponse); err != nil {
		return nil, fmt.Errorf("error parsing response: %w", err)
	}

	// Convert to GraphQL response
	results := make([]*model.Location, 0, len(esResponse.Hits.Hits))
	for _, hit := range esResponse.Hits.Hits {
		loc := convertToLocation(hit)
		results = append(results, loc)
	}

	// Perform validation if parent filters provided
	validation := performValidation(input, results)

	response := &model.LocationSearchResponse{
		Results:    results,
		Total:      esResponse.Hits.Total.Value,
		Took:       esResponse.Took,
		Validation: validation,
	}

	return response, nil
}

// Health check resolver
func (r *queryResolver) Health(ctx context.Context) (*model.HealthStatus, error) {
	status := "healthy"
	esStatus := "connected"

	// Test Elasticsearch connection
	res, err := r.ESClient.Info()
	if err != nil {
		esStatus = "disconnected"
		status = "degraded"
	} else {
		res.Body.Close()
	}

	return &model.HealthStatus{
		Status:        status,
		Elasticsearch: esStatus,
		Version:       "1.0.0",
	}, nil
}

// buildSearchQuery creates Elasticsearch query with fuzzy matching
func buildSearchQuery(input model.LocationSearchInput, limit int) map[string]interface{} {
	// Build multi-match query with fuzzy search
	mustClauses := []map[string]interface{}{
		{
			"multi_match": map[string]interface{}{
				"query":     input.Query,
				"fields":    []string{"name^3", "name_ne^3", "name_en^3", "name.fuzzy^2", "name_ne.fuzzy^2", "name_en.fuzzy^2", "search_text"},
				"fuzziness": "AUTO",
				"type":      "best_fields",
			},
		},
	}

	// Add parent filters if provided (for validation)
	if input.Ward != nil {
		mustClauses = append(mustClauses, map[string]interface{}{
			"term": map[string]interface{}{
				"ward": *input.Ward,
			},
		})
	}

	if input.Municipality != nil && *input.Municipality != "" {
		mustClauses = append(mustClauses, map[string]interface{}{
			"multi_match": map[string]interface{}{
				"query":  *input.Municipality,
				"fields": []string{"municipality.keyword", "municipality_ne.keyword"},
				"type":   "best_fields",
			},
		})
	}

	if input.District != nil && *input.District != "" {
		mustClauses = append(mustClauses, map[string]interface{}{
			"multi_match": map[string]interface{}{
				"query":  *input.District,
				"fields": []string{"district.keyword", "district_ne.keyword"},
				"type":   "best_fields",
			},
		})
	}

	if input.Province != nil && *input.Province != "" {
		mustClauses = append(mustClauses, map[string]interface{}{
			"multi_match": map[string]interface{}{
				"query":  *input.Province,
				"fields": []string{"province.keyword", "province_ne.keyword"},
				"type":   "best_fields",
			},
		})
	}

	query := map[string]interface{}{
		"size": limit,
		"query": map[string]interface{}{
			"bool": map[string]interface{}{
				"must": mustClauses,
			},
		},
		"sort": []map[string]interface{}{
			{
				"_score": map[string]interface{}{
					"order": "desc",
				},
			},
			{
				"boost_score": map[string]interface{}{
					"order": "desc",
				},
			},
		},
	}

	return query
}

// performValidation checks if parent filters match results
func performValidation(input model.LocationSearchInput, results []*model.Location) *model.ValidationResult {
	// Only validate if parent filters are provided
	hasFilters := input.Ward != nil ||
		(input.Municipality != nil && *input.Municipality != "") ||
		(input.District != nil && *input.District != "") ||
		(input.Province != nil && *input.Province != "")

	if !hasFilters {
		return nil
	}

	if len(results) == 0 {
		return &model.ValidationResult{
			Valid:   false,
			Message: strPtr("No results found matching the provided criteria"),
		}
	}

	// Check first result for validation
	mismatches := []*model.ValidationMismatch{}
	topResult := results[0]

	if input.Ward != nil && topResult.Ward != input.Ward {
		mismatches = append(mismatches, &model.ValidationMismatch{
			Field:    "ward",
			Expected: fmt.Sprintf("%d", *input.Ward),
			Actual:   ptrIntToStr(topResult.Ward),
		})
	}

	if input.Municipality != nil && *input.Municipality != "" {
		if topResult.Municipality == nil || !stringsMatch(*input.Municipality, *topResult.Municipality) {
			mismatches = append(mismatches, &model.ValidationMismatch{
				Field:    "municipality",
				Expected: *input.Municipality,
				Actual:   ptrToStr(topResult.Municipality),
			})
		}
	}

	if input.District != nil && *input.District != "" {
		if topResult.District == nil || !stringsMatch(*input.District, *topResult.District) {
			mismatches = append(mismatches, &model.ValidationMismatch{
				Field:    "district",
				Expected: *input.District,
				Actual:   ptrToStr(topResult.District),
			})
		}
	}

	if input.Province != nil && *input.Province != "" {
		if topResult.Province == nil || !stringsMatch(*input.Province, *topResult.Province) {
			mismatches = append(mismatches, &model.ValidationMismatch{
				Field:    "province",
				Expected: *input.Province,
				Actual:   ptrToStr(topResult.Province),
			})
		}
	}

	valid := len(mismatches) == 0
	message := "All parent locations match"
	if !valid {
		message = fmt.Sprintf("Found %d mismatch(es) in parent location hierarchy", len(mismatches))
	}

	return &model.ValidationResult{
		Valid:      valid,
		Mismatches: mismatches,
		Message:    &message,
	}
}

// convertToLocation converts ES hit to GraphQL Location
func convertToLocation(hit ESHit) *model.Location {
	src := hit.Source

	return &model.Location{
		ID:             hit.ID,
		EntityType:     src.EntityType,
		Name:           src.Name,
		NameNe:         &src.NameNe,
		NameEn:         &src.NameEn,
		PlaceType:      &src.PlaceType,
		AdminLevel:     &src.AdminLevel,
		Location:       convertGeoPoint(src.Location),
		Ward:           &src.Ward,
		Municipality:   &src.Municipality,
		MunicipalityNe: &src.MunicipalityNe,
		District:       &src.District,
		DistrictNe:     &src.DistrictNe,
		Province:       &src.Province,
		ProvinceNe:     &src.ProvinceNe,
		Country:        src.Country,
		Score:          hit.Score,
	}
}

// convertGeoPoint converts ES geo_point to GraphQL GeoPoint
func convertGeoPoint(loc ESGeoPoint) *model.GeoPoint {
	if loc.Lat == 0 && loc.Lon == 0 {
		return nil
	}
	return &model.GeoPoint{
		Lat: loc.Lat,
		Lon: loc.Lon,
	}
}

// Helper functions
func strPtr(s string) *string {
	return &s
}

func ptrToStr(s *string) *string {
	if s == nil {
		return strPtr("null")
	}
	return s
}

func ptrIntToStr(i *int) *string {
	if i == nil {
		return strPtr("null")
	}
	return strPtr(fmt.Sprintf("%d", *i))
}

func stringsMatch(a, b string) bool {
	return strings.EqualFold(strings.TrimSpace(a), strings.TrimSpace(b))
}

// Elasticsearch response structures
type ElasticsearchResponse struct {
	Took int `json:"took"`
	Hits struct {
		Total struct {
			Value int `json:"value"`
		} `json:"total"`
		Hits []ESHit `json:"hits"`
	} `json:"hits"`
}

type ESHit struct {
	Index  string   `json:"_index"`
	ID     string   `json:"_id"`
	Score  float64  `json:"_score"`
	Source ESSource `json:"_source"`
}

type ESSource struct {
	EntityType     string     `json:"entity_type"`
	Name           string     `json:"name"`
	NameNe         string     `json:"name_ne"`
	NameEn         string     `json:"name_en"`
	PlaceType      string     `json:"place_type"`
	AdminLevel     int        `json:"admin_level"`
	Location       ESGeoPoint `json:"location"`
	Ward           int        `json:"ward"`
	Municipality   string     `json:"municipality"`
	MunicipalityNe string     `json:"municipality_ne"`
	District       string     `json:"district"`
	DistrictNe     string     `json:"district_ne"`
	Province       string     `json:"province"`
	ProvinceNe     string     `json:"province_ne"`
	Country        string     `json:"country"`
	BoostScore     float64    `json:"boost_score"`
}

type ESGeoPoint struct {
	Lat float64 `json:"lat"`
	Lon float64 `json:"lon"`
}
