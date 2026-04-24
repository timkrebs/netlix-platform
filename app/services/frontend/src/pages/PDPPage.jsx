import React, { useEffect, useMemo, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import ProductTile from '../components/ProductTile.jsx';
import ProductCard from '../components/ProductCard.jsx';
import QtyStepper from '../components/QtyStepper.jsx';
import { fmtPrice } from '../lib/format.js';

export default function PDPPage({ products, loading, error, refetch, onAddToCart }) {
  const { id } = useParams();
  const navigate = useNavigate();
  const productId = Number(id);

  const product = useMemo(
    () => products.find((p) => p.id === productId),
    [products, productId],
  );

  const [size, setSize] = useState(null);
  const [qty, setQty] = useState(1);
  const [activeThumb, setActiveThumb] = useState(0);

  useEffect(() => {
    if (product && product.sizes?.length && !product.sizes.includes(size)) {
      setSize(product.sizes[0]);
    }
  }, [product, size]);

  useEffect(() => {
    window.scrollTo(0, 0);
  }, [productId]);

  if (loading && !product) {
    return (
      <section className="t-pdp">
        <nav className="t-crumbs">
          <button type="button" onClick={() => navigate('/')}>SHOP</button>
          <span>/</span>
          <span>…</span>
        </nav>
        <div className="t-pdp-grid">
          <div className="t-pdp-media">
            <div className="t-skel" style={{ aspectRatio: '1 / 1' }} />
          </div>
          <div className="t-pdp-info">
            <div className="t-skel t-skel-line" style={{ width: 120, marginBottom: 16 }} />
            <div className="t-skel" style={{ height: 36, width: '70%', marginBottom: 16 }} />
            <div className="t-skel t-skel-line" style={{ width: 80 }} />
          </div>
        </div>
      </section>
    );
  }

  if (error && !product) {
    return (
      <section className="t-pdp">
        <nav className="t-crumbs">
          <button type="button" onClick={() => navigate('/')}>SHOP</button>
          <span>/</span>
          <span>error</span>
        </nav>
        <div className="t-page-empty">
          <div className="t-empty-mark">∅</div>
          <div>Product unavailable.</div>
          <div style={{ display: 'flex', gap: 8 }}>
            {refetch && (
              <button type="button" className="t-btn-ghost" onClick={refetch}>RETRY</button>
            )}
            <button type="button" className="t-btn-ghost" onClick={() => navigate('/')}>BACK TO SHOP</button>
          </div>
        </div>
      </section>
    );
  }

  if (!product) {
    return (
      <section className="t-pdp">
        <nav className="t-crumbs">
          <button type="button" onClick={() => navigate('/')}>SHOP</button>
          <span>/</span>
          <span>not found</span>
        </nav>
        <div className="t-page-empty">
          <div className="t-empty-mark">∅</div>
          <div>No SKU matches that id.</div>
          <button type="button" className="t-btn-ghost" onClick={() => navigate('/')}>BACK TO SHOP</button>
        </div>
      </section>
    );
  }

  const related = products.filter((p) => p.id !== product.id).slice(0, 3);
  const soldOut = product.stock === 0;
  const ctaLabel = soldOut ? 'SOLD OUT' : `ADD TO CART · ${fmtPrice(product.price_cents * qty)}`;

  return (
    <section className="t-pdp">
      <nav className="t-crumbs" aria-label="Breadcrumb">
        <button type="button" onClick={() => navigate('/')}>SHOP</button>
        <span>/</span>
        <span>{(product.category || '').toUpperCase()}</span>
        <span>/</span>
        <span style={{ color: 'var(--fg)' }}>{product.sku}</span>
      </nav>

      <div className="t-pdp-grid">
        <div className="t-pdp-media">
          <ProductTile product={product} aspect="1/1" />
          <div className="t-pdp-thumbs">
            {[0, 1, 2, 3].map((i) => (
              <button
                key={i}
                type="button"
                className={'t-pdp-thumb' + (i === activeThumb ? ' is-on' : '')}
                onClick={() => setActiveThumb(i)}
                aria-label={`View angle ${i + 1}`}
                aria-pressed={i === activeThumb}
              >
                <ProductTile product={{ ...product, id: `${product.id}-${i}`, sku: `${product.sku}-${i}` }} small />
              </button>
            ))}
          </div>
        </div>

        <div className="t-pdp-info">
          <div className="t-pdp-meta">
            <span>{product.sku}</span>
            <span>IN STOCK · {product.stock}</span>
          </div>
          <h1 className="t-pdp-title">{product.title}</h1>
          <div className="t-pdp-price">{fmtPrice(product.price_cents)}</div>
          <p className="t-pdp-desc">{product.description}</p>

          {product.sizes?.length > 0 && (
            <div className="t-pdp-block">
              <div className="t-pdp-label">SIZE</div>
              <div className="t-size-grid">
                {product.sizes.map((s) => (
                  <button
                    key={s}
                    type="button"
                    className={'t-size-chip' + (size === s ? ' is-on' : '')}
                    onClick={() => setSize(s)}
                    aria-pressed={size === s}
                  >
                    {s}
                  </button>
                ))}
              </div>
            </div>
          )}

          <div className="t-pdp-block">
            <div className="t-pdp-label">QUANTITY</div>
            <QtyStepper value={qty} onChange={setQty} min={1} max={Math.max(1, product.stock)} />
          </div>

          <div className="t-pdp-cta">
            <button
              type="button"
              className="t-btn-primary"
              disabled={soldOut}
              onClick={() => onAddToCart?.(product, qty)}
            >
              {ctaLabel}
            </button>
            <button type="button" className="t-btn-ghost">SAVE</button>
          </div>

          <dl className="t-specs">
            <div><dt>SKU</dt><dd>{product.sku}</dd></div>
            <div><dt>Category</dt><dd>{product.category}</dd></div>
            <div><dt>Weight</dt><dd>{product.weight_g ? `${product.weight_g}g` : '—'}</dd></div>
            <div><dt>Origin</dt><dd>Portugal</dd></div>
            <div><dt>Lead time</dt><dd>3–5 business days</dd></div>
            <div><dt>Returns</dt><dd>30 days, free</dd></div>
          </dl>
        </div>
      </div>

      {related.length > 0 && (
        <section className="t-related" aria-label="Related products">
          <div className="t-related-head">
            <span>RELATED SKUs</span>
            <span style={{ color: 'var(--fg-mute)' }}>
              {String(related.length).padStart(2, '0')} ITEMS
            </span>
          </div>
          <div className="t-related-grid">
            {related.map((p, i) => (
              <ProductCard
                key={p.id}
                product={p}
                index={i}
                total={related.length}
                onOpen={() => navigate(`/p/${p.id}`)}
                onAdd={() => onAddToCart?.(p, 1)}
              />
            ))}
          </div>
        </section>
      )}
    </section>
  );
}
