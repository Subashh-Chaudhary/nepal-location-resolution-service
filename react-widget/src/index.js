import React, { useState, useEffect } from 'react';
import ReactDOM from 'react-dom/client';

/**
 * Nepal Location Search Widget
 * 
 * Embeddable search widget for Nepal locations with live GraphQL integration.
 * 
 * Usage: Embed via <script src="http://search.eshasan.local/widget.js"></script>
 */

const styles = {
  container: {
    fontFamily: 'Arial, sans-serif',
    maxWidth: '800px',
    margin: '10px',
    padding: '15px',
    border: '1px solid #ddd',
    borderRadius: '8px',
    backgroundColor: '#f9f9f9'
  },
  title: {
    margin: '0 0 10px 0',
    fontSize: '16px',
    color: '#333'
  },
  inputContainer: {
    display: 'flex',
    gap: '8px',
    marginBottom: '15px'
  },
  input: {
    flex: 1,
    padding: '10px',
    fontSize: '14px',
    border: '1px solid #ccc',
    borderRadius: '4px',
    outline: 'none'
  },
  button: {
    padding: '10px 16px',
    fontSize: '14px',
    backgroundColor: '#007bff',
    color: 'white',
    border: 'none',
    borderRadius: '4px',
    cursor: 'pointer'
  },
  status: {
    marginBottom: '10px',
    fontSize: '12px',
    color: '#666'
  },
  resultsContainer: {
    marginTop: '15px',
    padding: '10px',
    backgroundColor: '#fff',
    border: '1px solid #ddd',
    borderRadius: '4px',
    maxHeight: '500px',
    overflowY: 'auto'
  },
  jsonDisplay: {
    fontFamily: 'monospace',
    fontSize: '12px',
    whiteSpace: 'pre-wrap',
    wordBreak: 'break-word',
    lineHeight: '1.5'
  },
  loading: {
    color: '#007bff',
    fontStyle: 'italic'
  },
  error: {
    color: '#dc3545',
    padding: '10px',
    backgroundColor: '#f8d7da',
    borderRadius: '4px'
  }
};

function NepalLocationSearchWidget() {
  const [searchQuery, setSearchQuery] = useState('');
  const [statusMessage, setStatusMessage] = useState('Ready to search... (Type to see live results)');
  const [results, setResults] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  // Live search with debounce
  useEffect(() => {
    if (!searchQuery.trim()) {
      setResults(null);
      setStatusMessage('Ready to search... (Type to see live results)');
      return;
    }

    const timeoutId = setTimeout(() => {
      performSearch(searchQuery);
    }, 300); // 300ms debounce

    return () => clearTimeout(timeoutId);
  }, [searchQuery]);

  const performSearch = async (query) => {
    setLoading(true);
    setError(null);
    setStatusMessage(`Searching for: "${query}"...`);

    const graphqlQuery = `
      query SearchLocation($query: String!, $limit: Int!) {
        searchLocation(input: {query: $query, limit: $limit}) {
          total
          took
          results {
            id
            name
            nameNe
            nameEn
            entityType
            municipality
            municipalityNe
            district
            districtNe
            province
            provinceNe
            country
            location {
              lat
              lon
            }
            score
          }
        }
      }
    `;

    try {
      const response = await fetch('http://search.eshasan.local/graphql', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          query: graphqlQuery,
          variables: {
            query: query,
            limit: 10
          }
        })
      });

      const data = await response.json();
      
      if (data.errors) {
        throw new Error(data.errors[0].message);
      }

      setResults(data);
      const total = data.data?.searchLocation?.total || 0;
      const took = data.data?.searchLocation?.took || 0;
      setStatusMessage(`Found ${total} results in ${took}ms`);
    } catch (err) {
      setError(err.message);
      setStatusMessage('Search failed');
      console.error('[Nepal Location Widget] Search error:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleSearch = () => {
    if (!searchQuery.trim()) {
      setStatusMessage('Please enter a location to search');
      return;
    }
    performSearch(searchQuery);
  };

  const handleKeyPress = (e) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  return (
    <div style={styles.container}>
      <h3 style={styles.title}>🇳🇵 Nepal Location Search (Live)</h3>
      <div style={styles.inputContainer}>
        <input
          type="text"
          placeholder="Enter location (e.g., Kathmandu, Lazimpat, Imadol)..."
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          onKeyPress={handleKeyPress}
          style={styles.input}
        />
        <button onClick={handleSearch} style={styles.button} disabled={loading}>
          {loading ? 'Searching...' : 'Search'}
        </button>
      </div>
      <p style={styles.status}>
        {loading && <span style={styles.loading}>⏳ </span>}
        {statusMessage}
      </p>

      {error && (
        <div style={styles.error}>
          <strong>Error:</strong> {error}
        </div>
      )}

      {results && (
        <div style={styles.resultsContainer}>
          <pre style={styles.jsonDisplay}>
            {JSON.stringify(results, null, 2)}
          </pre>
        </div>
      )}
    </div>
  );
}

// Auto-mount widget when script is loaded
function initWidget() {
  // Look for container element or create one
  let container = document.getElementById('nepal-location-widget');
  
  if (!container) {
    container = document.createElement('div');
    container.id = 'nepal-location-widget';
    document.body.appendChild(container);
  }

  const root = ReactDOM.createRoot(container);
  root.render(<NepalLocationSearchWidget />);
  
  console.log('[Nepal Location Widget] Initialized successfully');
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', initWidget);
} else {
  initWidget();
}

// Export for programmatic use
export { NepalLocationSearchWidget, initWidget };
