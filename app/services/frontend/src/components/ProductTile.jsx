import React from 'react';
import { hashHue } from '../lib/format.js';

export default function ProductTile({ product, aspect = '1/1', small = false }) {
  const hue = hashHue(product.sku);
  const bg = `oklch(0.28 0.04 ${hue})`;
  const fg = `oklch(0.85 0.08 ${hue})`;
  const stripe = `oklch(0.24 0.04 ${hue})`;
  const uid = `tile-${product.id}-${product.sku}`;
  return (
    <div style={{ aspectRatio: aspect, background: bg, position: 'relative', overflow: 'hidden' }}>
      <svg viewBox="0 0 100 100" preserveAspectRatio="none" width="100%" height="100%" style={{ display: 'block' }} aria-hidden="true">
        <defs>
          <pattern id={uid} width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="8" height="8" fill={bg} />
            <rect width="1" height="8" fill={stripe} />
          </pattern>
        </defs>
        <rect width="100" height="100" fill={`url(#${uid})`} />
      </svg>
      {!small && (
        <div
          style={{
            position: 'absolute',
            inset: 0,
            display: 'flex',
            flexDirection: 'column',
            justifyContent: 'space-between',
            padding: '10px 12px',
            fontFamily: 'var(--font-mono)',
            fontSize: 10,
            color: fg,
            letterSpacing: '0.04em',
            textTransform: 'uppercase',
            pointerEvents: 'none',
          }}
        >
          <span>{product.sku}</span>
          <span style={{ textAlign: 'right', opacity: 0.6 }}>[product shot]</span>
        </div>
      )}
    </div>
  );
}
