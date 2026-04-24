import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import ProductTile from '../components/ProductTile.jsx';
import QtyStepper from '../components/QtyStepper.jsx';
import Totals from '../components/Totals.jsx';
import { fmtPrice } from '../lib/format.js';

export default function CartPage({ cart, products, productsLoading, setQty, onCheckout }) {
  const navigate = useNavigate();
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const lines = products.filter((p) => cart[p.id]);
  const hasCart = Object.keys(cart).length > 0;
  const showLoading = productsLoading && hasCart && lines.length === 0;
  const skuCount = lines.length;
  const unitCount = lines.reduce((a, p) => a + cart[p.id], 0);
  const subtotalCents = lines.reduce((s, p) => s + p.price_cents * cart[p.id], 0);

  async function checkout() {
    setError('');
    setSubmitting(true);
    const res = await onCheckout?.();
    if (res && !res.ok && !res.needsAuth) {
      setError(res.error || 'Checkout failed.');
    }
    setSubmitting(false);
  }

  return (
    <section className="t-page">
      <div className="t-page-head">
        <h1>CART</h1>
        <div className="t-page-meta">
          {String(skuCount).padStart(2, '0')} SKU · {String(unitCount).padStart(2, '0')} UNITS
        </div>
      </div>

      {showLoading ? (
        <div className="t-page-empty">
          <div className="t-loading" style={{ margin: 0, fontSize: 14 }}>SYNC…</div>
        </div>
      ) : lines.length === 0 ? (
        <div className="t-page-empty">
          <div className="t-empty-mark">∅</div>
          <div>Your cart is empty.</div>
          <button
            type="button"
            className="t-btn-primary"
            style={{ flex: '0 0 auto', padding: '14px 24px' }}
            onClick={() => navigate('/')}
          >
            BROWSE CATALOG
          </button>
        </div>
      ) : (
        <div className="t-cart-layout">
          <table className="t-cart-table">
            <thead>
              <tr>
                <th>SKU</th>
                <th>Item</th>
                <th>Size</th>
                <th>Unit</th>
                <th>Qty</th>
                <th>Line total</th>
                <th aria-label="Remove" />
              </tr>
            </thead>
            <tbody>
              {lines.map((p) => (
                <tr key={p.id}>
                  <td className="t-mono">{p.sku}</td>
                  <td>
                    <div className="t-cart-item">
                      <div className="t-cart-thumb">
                        <ProductTile product={p} small />
                      </div>
                      <div>
                        <div>{p.title}</div>
                        <div className="t-cart-cat">{p.category}</div>
                      </div>
                    </div>
                  </td>
                  <td>{(p.sizes && p.sizes[0]) || '—'}</td>
                  <td className="t-mono">{fmtPrice(p.price_cents)}</td>
                  <td>
                    <QtyStepper
                      value={cart[p.id]}
                      onChange={(n) => setQty(p.id, n)}
                      min={0}
                      max={p.stock}
                      size="mini"
                      ariaLabel={`Quantity for ${p.title}`}
                    />
                  </td>
                  <td className="t-mono">{fmtPrice(p.price_cents * cart[p.id])}</td>
                  <td>
                    <button
                      type="button"
                      className="t-drawer-remove"
                      onClick={() => setQty(p.id, 0)}
                      aria-label={`Remove ${p.title}`}
                    >
                      ×
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>

          <aside className="t-cart-sum">
            <div className="t-sum-head">ORDER SUMMARY</div>
            {error && (
              <div
                role="alert"
                style={{
                  fontFamily: 'var(--font-mono)',
                  fontSize: 11,
                  color: 'var(--warn)',
                  letterSpacing: '0.04em',
                  marginBottom: 12,
                }}
              >
                {error}
              </div>
            )}
            <Totals subtotalCents={subtotalCents} />
            <button
              type="button"
              className="t-btn-primary"
              disabled={submitting}
              onClick={checkout}
            >
              {submitting ? '…' : 'CHECKOUT →'}
            </button>
            <div className="t-sum-fine">
              <div>· Free returns within 30 days</div>
              <div>· Orders ship from Rotterdam, NL</div>
              <div>· Estimated delivery 3–5 business days</div>
            </div>
          </aside>
        </div>
      )}
    </section>
  );
}
