import React from 'react';
import ProductCard from './ProductCard.jsx';

function Skeleton() {
  return (
    <article className="t-card t-card-skeleton" aria-hidden="true">
      <div className="t-card-media t-skel" style={{ aspectRatio: '1 / 1' }} />
      <div className="t-card-body">
        <div className="t-skel t-skel-line" />
        <div className="t-skel t-skel-line t-skel-line-short" />
        <div className="t-skel t-skel-line" />
      </div>
    </article>
  );
}

export default function ProductGrid({
  products,
  loading,
  error,
  density = 'spacious',
  onOpen,
  onAdd,
  onReset,
  onRetry,
  totalCount,
}) {
  const cls = `t-grid t-grid-${density}`;

  if (error) {
    return (
      <section className={cls}>
        <div className="t-empty">
          <div className="t-empty-mark">∅</div>
          <div>Catalog unavailable.</div>
          <button type="button" className="t-btn-ghost" onClick={onRetry}>
            RETRY
          </button>
        </div>
      </section>
    );
  }

  if (loading && products.length === 0) {
    const count = density === 'compact' ? 8 : 6;
    return (
      <section className={cls}>
        {Array.from({ length: count }).map((_, i) => (
          <Skeleton key={i} />
        ))}
      </section>
    );
  }

  if (products.length === 0) {
    return (
      <section className={cls}>
        <div className="t-empty">
          <div className="t-empty-mark">∅</div>
          <div>No SKUs match these filters.</div>
          <button type="button" className="t-btn-ghost" onClick={onReset}>
            RESET FILTERS
          </button>
        </div>
      </section>
    );
  }

  return (
    <section className={cls}>
      {products.map((p, i) => (
        <ProductCard
          key={p.id}
          product={p}
          index={i}
          total={totalCount}
          onOpen={() => onOpen?.(p)}
          onAdd={() => onAdd?.(p)}
        />
      ))}
    </section>
  );
}
