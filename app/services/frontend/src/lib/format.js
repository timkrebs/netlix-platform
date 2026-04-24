export function fmtPrice(cents) {
  return `$${(cents / 100).toFixed(2)}`;
}

export function fmtPriceCompact(cents) {
  return `${(cents / 100).toFixed(2)}`;
}

export function hashHue(s) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h % 360;
}
