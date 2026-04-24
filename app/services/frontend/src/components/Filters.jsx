import React from 'react';

const SIZES = ['All', 'S', 'M', 'L', 'XL', 'OS'];

function DensitySpaciousIcon() {
  return (
    <svg width="14" height="10" viewBox="0 0 14 10" fill="currentColor" aria-hidden="true">
      <rect x="0" y="0" width="4" height="4" />
      <rect x="5" y="0" width="4" height="4" />
      <rect x="10" y="0" width="4" height="4" />
      <rect x="0" y="6" width="4" height="4" />
      <rect x="5" y="6" width="4" height="4" />
      <rect x="10" y="6" width="4" height="4" />
    </svg>
  );
}

function DensityCompactIcon() {
  return (
    <svg width="15" height="10" viewBox="0 0 15 10" fill="currentColor" aria-hidden="true">
      <rect x="0" y="0" width="3" height="4" />
      <rect x="4" y="0" width="3" height="4" />
      <rect x="8" y="0" width="3" height="4" />
      <rect x="12" y="0" width="3" height="4" />
      <rect x="0" y="6" width="3" height="4" />
      <rect x="4" y="6" width="3" height="4" />
      <rect x="8" y="6" width="3" height="4" />
      <rect x="12" y="6" width="3" height="4" />
    </svg>
  );
}

export default function Filters({
  filters,
  setFilters,
  categories,
  filteredCount,
  totalCount,
  loading,
  density,
  setDensity,
}) {
  const cats = ['All', ...categories];
  return (
    <details className="t-filters" open>
      <summary className="t-filters-summary">
        <span>
          FILTERS{' '}
          <span style={{ color: 'var(--fg-mute)' }}>
            [{filteredCount}/{totalCount}]
          </span>
        </span>
        <svg
          className="t-filters-summary-arrow"
          width="10"
          height="6"
          viewBox="0 0 10 6"
          fill="none"
          aria-hidden="true"
        >
          <path d="M1 1l4 4 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="square" />
        </svg>
      </summary>
      <div className="t-filters-inner">
      <div className="t-filter-head">
        <span>FILTERS</span>
        <span style={{ color: 'var(--fg-mute)' }}>
          [{filteredCount}/{totalCount}]
        </span>
      </div>

      <div className="t-filter-group">
        <div className="t-filter-label">CATEGORY</div>
        {cats.map((c) => (
          <label key={c} className="t-filter-opt">
            <input
              type="radio"
              name="category"
              checked={filters.category === c}
              onChange={() => setFilters({ category: c })}
            />
            <span>{c}</span>
          </label>
        ))}
      </div>

      <div className="t-filter-group">
        <div className="t-filter-label">SIZE</div>
        <div className="t-size-grid">
          {SIZES.map((s) => (
            <button
              key={s}
              type="button"
              className={'t-size-chip' + (filters.size === s ? ' is-on' : '')}
              onClick={() => setFilters({ size: s })}
            >
              {s}
            </button>
          ))}
        </div>
      </div>

      <div className="t-filter-group">
        <div className="t-filter-label">
          PRICE · MAX{' '}
          <span style={{ color: 'var(--fg)' }}>
            ${(filters.priceMax / 100).toFixed(0)}
          </span>
        </div>
        <input
          type="range"
          min="500"
          max="6000"
          step="100"
          value={filters.priceMax}
          onChange={(e) => setFilters({ priceMax: Number(e.target.value) })}
          className="t-range"
          aria-label="Maximum price"
        />
        <div className="t-range-scale">
          <span>$5</span>
          <span>$60</span>
        </div>
      </div>

      {loading && <div className="t-loading">SYNC…</div>}

      {setDensity && (
        <div className="t-filter-group t-filter-density">
          <div className="t-filter-label">DENSITY</div>
          <div className="t-density-toggle">
            <button
              type="button"
              className={'t-density-btn' + (density === 'spacious' ? ' is-on' : '')}
              onClick={() => setDensity('spacious')}
              aria-pressed={density === 'spacious'}
              aria-label="Spacious layout (3 columns)"
              title="Spacious · 3 columns"
            >
              <DensitySpaciousIcon />
            </button>
            <button
              type="button"
              className={'t-density-btn' + (density === 'compact' ? ' is-on' : '')}
              onClick={() => setDensity('compact')}
              aria-pressed={density === 'compact'}
              aria-label="Compact layout (4 columns)"
              title="Compact · 4 columns"
            >
              <DensityCompactIcon />
            </button>
          </div>
        </div>
      )}
      </div>
    </details>
  );
}
