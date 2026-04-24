import React from 'react';
import { fmtPrice } from '../lib/format.js';
import { computeTotals, formatShipping } from '../lib/cart.js';

export default function Totals({ subtotalCents }) {
  const { shippingCents, taxCents, totalCents } = computeTotals(subtotalCents);
  return (
    <dl className="t-totals">
      <div>
        <dt>Subtotal</dt>
        <dd>{fmtPrice(subtotalCents)}</dd>
      </div>
      <div>
        <dt>Shipping</dt>
        <dd>{formatShipping(shippingCents)}</dd>
      </div>
      <div>
        <dt>Tax (9%)</dt>
        <dd>{fmtPrice(taxCents)}</dd>
      </div>
      <div className="is-total">
        <dt>Total</dt>
        <dd>{fmtPrice(totalCents)}</dd>
      </div>
    </dl>
  );
}
