import React from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { fmtPrice } from '../lib/format.js';

export default function CheckoutPage() {
  const location = useLocation();
  const navigate = useNavigate();
  const order = location.state?.order;
  const placedAt = location.state?.placedAt;

  if (!order) {
    return <Navigate to="/cart" replace />;
  }

  const placedStr = placedAt
    ? new Date(placedAt).toISOString().replace('T', ' ').slice(0, 19) + 'Z'
    : '—';
  const orderDisplayId = typeof order.id === 'number' ? `#${order.id}` : String(order.id);

  return (
    <section className="t-page">
      <div className="t-confirm">
        <div className="t-confirm-mark">✓</div>
        <div className="t-confirm-kicker">ORDER CONFIRMED</div>
        <h1 className="t-confirm-title">Packed. Paid. En route.</h1>
        <p className="t-confirm-sub">
          You'll receive a tracking number at the email on file within 24h.
          Reach us at{' '}
          <span style={{ color: 'var(--accent)' }}>support@netlix.shop</span>{' '}
          for anything weird.
        </p>
        <dl className="t-confirm-grid">
          <div>
            <dt>Order #</dt>
            <dd className="t-mono">{orderDisplayId}</dd>
          </div>
          <div>
            <dt>Placed</dt>
            <dd className="t-mono">{placedStr}</dd>
          </div>
          <div>
            <dt>Total</dt>
            <dd className="t-mono">{fmtPrice(order.total_cents)}</dd>
          </div>
          <div>
            <dt>ETA</dt>
            <dd className="t-mono">3–5 business days</dd>
          </div>
        </dl>
        <div className="t-confirm-cta">
          <button
            type="button"
            className="t-btn-primary"
            onClick={() => navigate('/orders')}
          >
            VIEW ORDER
          </button>
          <button
            type="button"
            className="t-btn-ghost"
            onClick={() => navigate('/')}
          >
            KEEP SHOPPING
          </button>
        </div>
      </div>
    </section>
  );
}
