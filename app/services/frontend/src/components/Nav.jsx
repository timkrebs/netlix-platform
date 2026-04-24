import React from 'react';

const NAV_ITEMS = [
  ['shop', 'Shop'],
  ['orders', 'Orders'],
  ['login', 'Account'],
];

export default function Nav({ view, onNavigate, cartCount = 0, onOpenCart }) {
  const today = new Date().toISOString().slice(0, 10);
  return (
    <>
      <div className="t-bar">
        <span>NETLIX/RETAIL · v1.04</span>
        <span className="t-bar-right">
          <span>
            <span style={{ color: 'var(--accent)' }}>●</span> SYS ONLINE
          </span>
          <span>·</span>
          <span>FREE SHIP &gt; $50</span>
          <span>·</span>
          <span>{today}</span>
        </span>
      </div>
      <header className="t-nav">
        <button className="t-logo" onClick={() => onNavigate?.('shop')} aria-label="Netlix home">
          <span className="t-logo-mark">▚</span>
          <span className="t-logo-word">NETLIX</span>
        </button>
        <nav className="t-nav-links" aria-label="Primary">
          {NAV_ITEMS.map(([id, label]) => (
            <button
              key={id}
              className={'t-nav-link' + (view === id ? ' is-active' : '')}
              onClick={() => onNavigate?.(id)}
              aria-current={view === id ? 'page' : undefined}
            >
              {label}
            </button>
          ))}
        </nav>
        <div className="t-nav-right">
          <button className="t-icon-btn" title="Search" aria-label="Search">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" aria-hidden="true">
              <circle cx="7" cy="7" r="4.5" stroke="currentColor" />
              <path d="M10.5 10.5L14 14" stroke="currentColor" strokeLinecap="square" />
            </svg>
          </button>
          <button className="t-cart-btn" onClick={onOpenCart} aria-label={`Cart (${cartCount} items)`}>
            CART <span className="t-cart-count">[{String(cartCount).padStart(2, '0')}]</span>
          </button>
        </div>
      </header>
    </>
  );
}
