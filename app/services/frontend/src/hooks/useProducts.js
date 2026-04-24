import { useCallback, useEffect, useState } from 'react';
import { api } from '../api.js';
import { seedBySku } from '../data/seed.js';

function enrich(row) {
  const seed = seedBySku[row.sku];
  return {
    ...row,
    category: seed?.category || 'Other',
    sizes: seed?.sizes || [],
    weight_g: seed?.weight_g,
  };
}

export default function useProducts() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const refetch = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const rows = await api.listProducts();
      setProducts((rows || []).map(enrich));
    } catch (err) {
      setError(err);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    refetch();
  }, [refetch]);

  return { products, loading, error, refetch };
}
