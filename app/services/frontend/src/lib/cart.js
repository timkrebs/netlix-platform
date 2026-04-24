import { fmtPrice } from './format.js';

export const FREE_SHIP_THRESHOLD_CENTS = 5000;
export const FLAT_SHIP_CENTS = 499;
export const TAX_RATE = 0.09;

export function computeTotals(subtotalCents) {
  const shippingCents = subtotalCents >= FREE_SHIP_THRESHOLD_CENTS || subtotalCents === 0
    ? 0
    : FLAT_SHIP_CENTS;
  const taxCents = Math.round(subtotalCents * TAX_RATE);
  const totalCents = subtotalCents + shippingCents + taxCents;
  return { subtotalCents, shippingCents, taxCents, totalCents };
}

export function formatShipping(shippingCents) {
  return shippingCents === 0 ? 'Free' : fmtPrice(shippingCents);
}
