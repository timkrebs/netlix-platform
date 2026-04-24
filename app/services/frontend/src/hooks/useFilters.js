import { useSearchParams } from 'react-router-dom';

export const DEFAULT_FILTERS = { category: 'All', size: 'All', priceMax: 6000 };

const KEYS = { category: 'category', size: 'size', priceMax: 'maxPrice' };

export default function useFilters() {
  const [params, setParams] = useSearchParams();

  const filters = {
    category: params.get(KEYS.category) || DEFAULT_FILTERS.category,
    size: params.get(KEYS.size) || DEFAULT_FILTERS.size,
    priceMax: Number(params.get(KEYS.priceMax)) || DEFAULT_FILTERS.priceMax,
  };

  function setFilters(patch) {
    const next = typeof patch === 'function' ? patch(filters) : { ...filters, ...patch };
    const p = new URLSearchParams(params);

    if (next.category && next.category !== DEFAULT_FILTERS.category) p.set(KEYS.category, next.category);
    else p.delete(KEYS.category);

    if (next.size && next.size !== DEFAULT_FILTERS.size) p.set(KEYS.size, next.size);
    else p.delete(KEYS.size);

    if (next.priceMax && next.priceMax !== DEFAULT_FILTERS.priceMax) p.set(KEYS.priceMax, String(next.priceMax));
    else p.delete(KEYS.priceMax);

    setParams(p, { replace: true });
  }

  function reset() {
    const p = new URLSearchParams(params);
    Object.values(KEYS).forEach((k) => p.delete(k));
    setParams(p, { replace: true });
  }

  return { filters, setFilters, reset };
}
