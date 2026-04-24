import React, { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api.js';
import { fmtPrice } from '../lib/format.js';

const STATUS_COLOR = {
  shipped: 'var(--accent)',
  delivered: 'var(--fg-dim)',
  pending: 'var(--warn)',
};

export default function OrdersPage({ userEmail, products, onReorder }) {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [reloadKey, setReloadKey] = useState(0);
  const navigate = useNavigate();

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError('');
    api
      .listOrders()
      .then((list) => {
        if (!cancelled) setOrders(Array.isArray(list) ? list : []);
      })
      .catch((e) => {
        if (!cancelled) setError(e.message || 'Could not load orders.');
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [reloadKey]);

  const productsById = useMemo(() => {
    const m = {};
    for (const p of products) m[p.id] = p;
    return m;
  }, [products]);

  return (
    <section className="t-page">
      <div className="t-page-head">
        <h1>ORDERS</h1>
        <div className="t-page-meta">
          {String(orders.length).padStart(2, '0')} RECORDS
          {userEmail ? ` · ${userEmail}` : ''}
        </div>
      </div>

      {loading && (
        <div className="t-page-empty">
          <div className="t-loading" style={{ margin: 0, fontSize: 14 }}>SYNC…</div>
        </div>
      )}

      {!loading && error && (
        <div className="t-page-empty">
          <div className="t-empty-mark">∅</div>
          <div>{error}</div>
          <button
            type="button"
            className="t-btn-ghost"
            onClick={() => setReloadKey((k) => k + 1)}
          >
            RETRY
          </button>
        </div>
      )}

      {!loading && !error && orders.length === 0 && (
        <div className="t-page-empty">
          <div className="t-empty-mark">∅</div>
          <div>No orders yet.</div>
          <button
            type="button"
            className="t-btn-primary"
            style={{ flex: '0 0 auto', padding: '14px 24px' }}
            onClick={() => navigate('/')}
          >
            BROWSE CATALOG
          </button>
        </div>
      )}

      {!loading && !error && orders.length > 0 && (
        <div className="t-orders">
          {orders.map((o) => (
            <OrderCard
              key={o.id}
              order={o}
              productsById={productsById}
              onReorder={() => onReorder?.(o)}
            />
          ))}
        </div>
      )}
    </section>
  );
}

function OrderCard({ order, productsById, onReorder }) {
  const rawStatus = String(order.status || 'pending').toLowerCase();
  const statusColor = STATUS_COLOR[rawStatus] || 'var(--fg-dim)';
  const placedSrc = order.placed || order.created_at || order.placed_at;
  const placedStr = placedSrc
    ? new Date(placedSrc).toISOString().slice(0, 10)
    : '—';

  return (
    <article className="t-order">
      <header className="t-order-head">
        <div>
          <div className="t-order-k">ORDER</div>
          <div className="t-order-v">#{order.id}</div>
        </div>
        <div>
          <div className="t-order-k">PLACED</div>
          <div className="t-order-v">{placedStr}</div>
        </div>
        <div>
          <div className="t-order-k">TOTAL</div>
          <div className="t-order-v">{fmtPrice(order.total_cents)}</div>
        </div>
        <div>
          <div className="t-order-k">STATUS</div>
          <div className="t-order-v" style={{ color: statusColor }}>
            ● {rawStatus.toUpperCase()}
          </div>
        </div>
        <button type="button" className="t-btn-ghost" onClick={onReorder}>
          REORDER
        </button>
      </header>
      <table className="t-order-items">
        <tbody>
          {(order.items || []).map((it, i) => {
            const product = productsById[it.product_id];
            const title = product?.title || `Product #${it.product_id}`;
            const sku = product?.sku || `#${it.product_id}`;
            const unitCents = it.price_cents ?? product?.price_cents ?? 0;
            const lineTotal = unitCents * it.quantity;
            return (
              <tr key={i}>
                <td
                  className="t-mono"
                  style={{ color: 'var(--fg-mute)', width: 40 }}
                >
                  {String(i + 1).padStart(2, '0')}
                </td>
                <td>{title}</td>
                <td className="t-mono" style={{ color: 'var(--fg-dim)' }}>
                  {sku}
                </td>
                <td className="t-mono" style={{ textAlign: 'right' }}>
                  × {it.quantity}
                </td>
                <td className="t-mono" style={{ textAlign: 'right' }}>
                  {fmtPrice(lineTotal)}
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </article>
  );
}
