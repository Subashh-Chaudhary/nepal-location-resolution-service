# Normalization Results & Data Quality Report

## Summary

Successfully normalized **23,348 places** from Nepal OSM dataset with spatial enrichment using admin boundaries.

### Data Counts
- **Admin Boundaries**: 7,587 total
  - Provinces (admin_level=4): 7
  - Districts (admin_level=6): 77
  - Municipalities (admin_level=7): 757
  - Wards (admin_level=9): 6,733
- **Places**: 23,348 (villages, hamlets, localities)
- **Named Roads**: 19,443
- **POI**: 97,718

## Spatial Enrichment Results

### Completeness Rates
```sql
-- Check enrichment completeness
SELECT 
    COUNT(*) as total_places,
    COUNT(province) as has_province,
    COUNT(district) as has_district,
    COUNT(municipality) as has_municipality,
    COUNT(ward) as has_ward,
    ROUND(100.0 * COUNT(province) / COUNT(*), 2) || '%' as province_pct,
    ROUND(100.0 * COUNT(district) / COUNT(*), 2) || '%' as district_pct,
    ROUND(100.0 * COUNT(municipality) / COUNT(*), 2) || '%' as municipality_pct,
    ROUND(100.0 * COUNT(ward) / COUNT(*), 2) || '%' as ward_pct
FROM normalized.places;
```

Expected results: ~100% province, ~100% district, ~4% municipality (from ward inference), ~97% ward

## Known Data Quality Issues

### 1. OSM Administrative Boundary Naming

**Issue**: Some districts use localized names that may not match official government sources.

**Example**: 
- OSM uses "नेपालगंज" (Nepalgunj) as the district name
- Official name is "Banke District"
- This is likely because OSM contributors used the Nepali name for the district

**Impact**: District names may not exactly match government databases. Cross-referencing requires mapping table.

**Sample affected places**:
```
name              | province        | district   | municipality
------------------+-----------------+------------+-------------
Piprihawa Gaun    | लुम्बिनी प्रदेश   | नेपालगंज     | NULL
Mahendranagar     | लुम्बिनी प्रदेश   | नेपालगंज     | NULL
```

### 2. Missing Municipality Boundaries (admin_level=7)

**Issue**: Many municipalities don't have `admin_level=7` boundaries in OSM, only ward boundaries exist.

**Workaround Implemented**: Municipality names are inferred from ward names when possible.
- Ward name pattern: `"Municipality-##"` (e.g., "Nepalgunj-01")
- Extracts municipality: `"Nepalgunj"`

**Effectiveness**: Successfully inferred 848 place-municipality relationships.

**Limitation**: Only works for places inside ward boundaries. Rural areas without wards remain NULL.

### 3. Spatial Precision Issues

**Root Cause**: Using `ST_Contains` instead of `ST_Intersects` for better precision.

**Trade-off**:
- ✅ More accurate: Only matches places truly inside boundaries
- ❌ Misses border cases: Places on boundary edges may not match

**Mitigation**: Used bounding box (`&&`) pre-filtering + ordered by smallest area first to handle overlapping boundaries.

### 4. Ward Number Extraction Challenges

**Issue**: Ward tags contain non-standard characters:
- Superscripts: "वडा नं १०¹"
- Unicode formatting: Various Devanagari number formats

**Solution**: Regex pattern removes all non-digit characters before casting to integer:
```sql
regexp_replace(ward_text, '\\D', '', 'g')::INTEGER
```

## Normalization Process

### 1. Admin Boundary Import
```sql
-- Filters applied:
WHERE boundary = 'administrative'  -- Only administrative boundaries
  AND admin_level IN (2,4,6,7,9)   -- Relevant levels only
```

### 2. Spatial Enrichment Strategy

**Approach**: Subquery-based updates with ST_Contains for precision

```sql
-- Example: Province assignment
UPDATE normalized.places p
SET province = (
  SELECT a.name
  FROM normalized.admin_boundaries a
  WHERE a.admin_level = 4
    AND p.centroid && a.geom              -- Bounding box filter (fast)
    AND ST_Contains(a.geom, p.centroid)   -- Precise containment check
  ORDER BY ST_Area(a.geom) ASC            -- Smallest matching boundary
  LIMIT 1
);
```

**Why this approach**:
- Handles overlapping boundaries (uses smallest)
- Precise containment (not just intersection)
- Indexed bounding box filter for performance

### 3. Municipality Inference from Wards

```sql
UPDATE normalized.places p
SET municipality = (
  SELECT regexp_replace(a.name, '-[0-9]+$', '')  -- "Nepalgunj-01" -> "Nepalgunj"
  FROM normalized.admin_boundaries a
  WHERE a.admin_level = 9
    AND a.name ~ '-[0-9]+$'  -- Has ward number pattern
    AND ST_Contains(a.geom, p.centroid)
  ORDER BY ST_Area(a.geom) ASC
  LIMIT 1
)
WHERE p.municipality IS NULL;
```

## Sample Verification Queries

### Check Overall Quality
```sql
SELECT 
    name, 
    province, 
    district, 
    municipality, 
    ward 
FROM normalized.places 
WHERE name IS NOT NULL 
ORDER BY RANDOM() 
LIMIT 20;
```

### Find Places Without Municipality
```sql
SELECT 
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE province IS NOT NULL) as has_province,
    COUNT(*) FILTER (WHERE district IS NOT NULL) as has_district,
    COUNT(*) FILTER (WHERE municipality IS NULL) as no_municipality
FROM normalized.places;
```

### Check Ward Coverage
```sql
SELECT 
    municipality,
    COUNT(*) as place_count,
    COUNT(DISTINCT ward) as ward_count
FROM normalized.places
WHERE municipality IS NOT NULL
GROUP BY municipality
ORDER BY place_count DESC
LIMIT 10;
```

## Recommendations for Production

### 1. Create District Name Mapping Table
```sql
CREATE TABLE normalized.district_name_mapping (
  osm_name TEXT PRIMARY KEY,
  official_name TEXT,
  official_name_en TEXT,
  notes TEXT
);

-- Example entries
INSERT INTO normalized.district_name_mapping VALUES
  ('नेपालगंज', 'बाँके जिल्ला', 'Banke District', 'OSM uses city name for district');
```

### 2. Manual Municipality Boundaries

For critical municipalities without OSM boundaries, consider:
1. Digitizing from government shapefiles
2. Contributing back to OpenStreetMap
3. Maintaining custom boundary layer

### 3. Periodic OSM Updates

OSM data improves over time. Schedule quarterly updates:
```bash
# Download latest Nepal extract
wget https://download.geofabrik.de/asia/nepal-latest.osm.pbf

# Re-import and normalize
./scripts/import_with_osm2pgsql.sh
psql -f sql/normalize_initial.sql
```

## Next Steps

1. **Validation**: Cross-reference with official CBS (Central Bureau of Statistics) data
2. **Completeness**: Identify and report missing boundaries to OSM community
3. **Enrichment**: Add English translations from government sources
4. **Search View**: Create denormalized `places_search_view` for Elasticsearch export
5. **API Integration**: Build location resolution API with fuzzy matching

## References

- Nepal Admin Levels: https://wiki.openstreetmap.org/wiki/Nepal/Administrative_divisions
- OSM Nepal: https://www.openstreetmap.org/relation/184633
- CBS Nepal: https://cbs.gov.np/
