import React from 'react';

export default function QtyStepper({ value, onChange, min = 0, max = Infinity, size = 'full', ariaLabel = 'Quantity' }) {
  const cls = size === 'mini' ? 't-qty-mini' : 't-qty';
  const dec = () => onChange(Math.max(min, value - 1));
  const inc = () => onChange(Math.min(max, value + 1));
  return (
    <div className={cls} role="group" aria-label={ariaLabel}>
      <button type="button" onClick={dec} disabled={value <= min} aria-label="Decrease">−</button>
      <span aria-live="polite">{value}</span>
      <button type="button" onClick={inc} disabled={value >= max} aria-label="Increase">+</button>
    </div>
  );
}
