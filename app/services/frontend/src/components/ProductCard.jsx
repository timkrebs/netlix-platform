import React from 'react';
import ProductTile from './ProductTile.jsx';
import { fmtPrice } from '../lib/format.js';

export default function ProductCard({ product, index, total, onOpen, onAdd }) {
  const stockPct = Math.min(100, (product.stock / 200) * 100);
  return (
    <article className="t-card">
      <button
        type="button"
        className="t-card-media"
        onClick={onOpen}
        aria-label={`Open ${product.title}`}
      >
        <ProductTile product={product} />
        <div className="t-card-index">
          {String(index + 1).padStart(2, '0')}/{String(total).padStart(2, '0')}
        </div>
      </button>
      <div className="t-card-body">
        <div className="t-card-meta">
          <span>{product.sku}</span>
          <span>{(product.category || '').toUpperCase()}</span>
        </div>
        <button type="button" className="t-card-title" onClick={onOpen}>
          {product.title}
        </button>
        <div className="t-card-foot">
          <span className="t-card-price">{fmtPrice(product.price_cents)}</span>
          <button
            type="button"
            className="t-add"
            disabled={product.stock === 0}
            onClick={onAdd}
            aria-label={`Add ${product.title} to cart`}
          >
            {product.stock === 0 ? 'SOLD OUT' : 'ADD +'}
          </button>
        </div>
        <div className="t-card-stock">
          <span className="t-card-stock-bar">
            <span style={{ width: `${stockPct}%` }} />
          </span>
          <span>{product.stock} in stock</span>
        </div>
      </div>
    </article>
  );
}
