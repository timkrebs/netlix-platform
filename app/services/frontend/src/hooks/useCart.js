import { useCallback, useEffect, useMemo, useState } from 'react';

const STORAGE_KEY = 'netlix_cart';

function load() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    const parsed = raw ? JSON.parse(raw) : null;
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

export default function useCart() {
  const [cart, setCart] = useState(load);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(cart));
    } catch { /* quota/disabled — tolerate */ }
  }, [cart]);

  const addToCart = useCallback((product, qty = 1) => {
    setCart((c) => ({ ...c, [product.id]: (c[product.id] || 0) + qty }));
  }, []);

  const setQty = useCallback((productId, n) => {
    setCart((c) => {
      const next = { ...c };
      if (n <= 0) delete next[productId];
      else next[productId] = n;
      return next;
    });
  }, []);

  const clear = useCallback(() => setCart({}), []);

  const count = useMemo(
    () => Object.values(cart).reduce((a, b) => a + b, 0),
    [cart],
  );

  return { cart, addToCart, setQty, clear, count };
}
