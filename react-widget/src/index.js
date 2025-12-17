import React, { useState } from 'react';
import ReactDOM from 'react-dom/client';

/**
 * Nepal Location Search Widget
 * 
 * This is a minimal embeddable search widget for Nepal locations.
 * Currently returns dummy content - logs input to console.
 * 
 * Usage: Embed via <script src="http://search.eshasan.local/widget.js"></script>
 */

const styles = {
  container: {
    fontFamily: 'Arial, sans-serif',
    maxWidth: '400px',
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
    gap: '8px'
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
    marginTop: '10px',
    fontSize: '12px',
    color: '#666'
  }
};

function NepalLocationSearchWidget() {
  const [searchQuery, setSearchQuery] = useState('');
  const [statusMessage, setStatusMessage] = useState('Ready to search...');

  const handleSearch = () => {
    if (!searchQuery.trim()) {
      setStatusMessage('Please enter a location to search');
      return;
    }

    // Dummy implementation - just logs to console
    console.log('[Nepal Location Widget] Search query:', searchQuery);
    setStatusMessage(`Searching for: "${searchQuery}" (dummy - check console)`);
    
    // In future: Make actual API call to /graphql
  };

  const handleKeyPress = (e) => {
    if (e.key === 'Enter') {
      handleSearch();
    }
  };

  return (
    <div style={styles.container}>
      <h3 style={styles.title}>🇳🇵 Nepal Location Search</h3>
      <div style={styles.inputContainer}>
        <input
          type="text"
          placeholder="Enter location (e.g., Kathmandu)"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          onKeyPress={handleKeyPress}
          style={styles.input}
        />
        <button onClick={handleSearch} style={styles.button}>
          Search
        </button>
      </div>
      <p style={styles.status}>{statusMessage}</p>
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
