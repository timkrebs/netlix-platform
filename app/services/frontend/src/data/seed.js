// Client-side metadata (category, sizes) merged by SKU into the catalog
// API response — the backend doesn't expose these fields today.
// Keep in sync with app/manifests/shop/sql/seed.sql (match by sku).

export const SEED_PRODUCTS = [
  { sku: 'NETLIX-TEE-BLK-M',  category: 'Apparel',     sizes: ['S', 'M', 'L', 'XL'],        weight_g: 220 },
  { sku: 'NETLIX-HOOD-NVY-L', category: 'Apparel',     sizes: ['S', 'M', 'L', 'XL', 'XXL'], weight_g: 780 },
  { sku: 'NETLIX-CAP-WHT',    category: 'Apparel',     sizes: ['OS'],                       weight_g: 90 },
  { sku: 'NETLIX-MUG-CER',    category: 'Objects',     sizes: ['OS'],                       weight_g: 340 },
  { sku: 'NETLIX-STICK-PACK', category: 'Accessories', sizes: ['OS'],                       weight_g: 20 },
  { sku: 'NETLIX-SOCK-CRW',   category: 'Apparel',     sizes: ['OS'],                       weight_g: 60 },
];

export const seedBySku = Object.fromEntries(SEED_PRODUCTS.map((p) => [p.sku, p]));
export const SEED_CATEGORIES = Array.from(new Set(SEED_PRODUCTS.map((p) => p.category)));
