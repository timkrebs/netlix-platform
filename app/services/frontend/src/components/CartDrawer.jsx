import React, { useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import ProductTile from './ProductTile.jsx';
import QtyStepper from './QtyStepper.jsx';
import { fmtPrice } from '../lib/format.js';
import {
  FREE_SHIP_THRESHOLD_CENTS,
  FLAT_SHIP_CENTS,
  formatShipping,
} from '../lib/cart.js';

export default function CartDrawer({ open, onClose, cart, products, productsLoading, setQty }) {
  const navigate = useNavigate();

  useEffect(() => {
    if (!open) return;
    function onKey(e) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  const lines = products.filter((p) => cart[p.id]);
  const hasCart = Object.keys(cart).length > 0;
  const showLoading = productsLoading && hasCart && lines.length === 0;
  const subtotalCents = lines.reduce((s, p) => s + p.price_cents * cart[p.id], 0);
  const shippingCents =
    subtotalCents === 0 || subtotalCents >= FREE_SHIP_THRESHOLD_CENTS ? 0 : FLAT_SHIP_CENTS;
  const totalCents = subtotalCents + shippingCents;

  function go(path) {
    onClose();
    navigate(path);
  }

  return (
    <>
      <div
        className={'t-overlay' + (open ? ' is-open' : '')}
        onClick={onClose}
        aria-hidden={!open}
      />
      <aside
        className={'t-drawer' + (open ? ' is-open' : '')}
        role="dialog"
        aria-modal="true"
        aria-label="Shopping cart"
        aria-hidden={!open}
      >
        <header className="t-drawer-head">
          <div>
            <div className="t-drawer-k">CART</div>
            <div className="t-drawer-v">
              {lines.length} line{lines.length === 1 ? '' : 's'}
            </div>
          </div>
          <button
            type="button"
            className="t-icon-btn"
            onClick={onClose}
            aria-label="Close cart"
          >
            <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true">
              <path
                d="M2 2L14 14M14 2L2 14"
                stroke="currentColor"
                strokeLinecap="square"
              />
            </svg>
          </button>
        </header>

        {showLoading ? (
          <div className="t-drawer-empty">
            <div className="t-loading" style={{ margin: 0, fontSize: 14 }}>SYNC…</div>
          </div>
        ) : lines.length === 0 ? (
          <div className="t-drawer-empty">
            <div className="t-empty-mark">∅</div>
            <div>Cart is empty.</div>
            <button type="button" className="t-btn-ghost" onClick={onClose}>
              KEEP BROWSING
            </button>
          </div>
        ) : (
          <>
            <ul className="t-drawer-lines">
              {lines.map((p) => (
                <li key={p.id} className="t-drawer-line">
                  <div className="t-drawer-thumb">
                    <ProductTile product={p} small />
                  </div>
                  <div className="t-drawer-info">
                    <div className="t-drawer-sku">{p.sku}</div>
                    <div className="t-drawer-name">{p.title}</div>
                    <div className="t-drawer-price">{fmtPrice(p.price_cents)}</div>
                  </div>
                  <div className="t-drawer-qty">
                    <QtyStepper
                      value={cart[p.id]}
                      onChange={(n) => setQty(p.id, n)}
                      min={0}
                      max={p.stock}
                      size="mini"
                      ariaLabel={`Quantity for ${p.title}`}
                    />
                    <button
                      type="button"
                      className="t-drawer-remove"
                      onClick={() => setQty(p.id, 0)}
                    >
                      REMOVE
                    </button>
                  </div>
                </li>
              ))}
            </ul>
            <footer className="t-drawer-foot">
              <dl className="t-totals">
                <div>
                  <dt>Subtotal</dt>
                  <dd>{fmtPrice(subtotalCents)}</dd>
                </div>
                <div>
                  <dt>Shipping</dt>
                  <dd>{formatShipping(shippingCents)}</dd>
                </div>
                <div className="is-total">
                  <dt>Total</dt>
                  <dd>{fmtPrice(totalCents)}</dd>
                </div>
              </dl>
              <button
                type="button"
                className="t-btn-primary"
                onClick={() => go('/cart')}
              >
                VIEW CART
              </button>
              <button
                type="button"
                className="t-btn-ghost"
                onClick={() => go('/checkout')}
              >
                CHECKOUT →
              </button>
            </footer>
          </>
        )}
      </aside>
    </>
  );
}
