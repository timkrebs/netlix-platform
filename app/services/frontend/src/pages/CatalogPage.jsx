import React, { useMemo } from 'react';
import Hero from '../components/Hero.jsx';
import PromoBanner from '../components/PromoBanner.jsx';
import Filters from '../components/Filters.jsx';
import ProductGrid from '../components/ProductGrid.jsx';
import useFilters from '../hooks/useFilters.js';
import useDensity from '../hooks/useDensity.js';
import { SEED_CATEGORIES } from '../data/seed.js';

export default function CatalogPage({
  products,
  loading,
  error,
  refetch,
  onOpenProduct,
  onAddToCart,
}) {
  const { filters, setFilters, reset } = useFilters();
  const { density, setDensity } = useDensity();

  const categories = useMemo(() => {
    const fromApi = Array.from(new Set(products.map((p) => p.category).filter(Boolean)));
    return fromApi.length ? fromApi : SEED_CATEGORIES;
  }, [products]);

  const filtered = useMemo(
    () =>
      products.filter((p) => {
        if (filters.category !== 'All' && p.category !== filters.category) return false;
        if (filters.size !== 'All' && !(p.sizes || []).includes(filters.size)) return false;
        if (p.price_cents > filters.priceMax) return false;
        return true;
      }),
    [products, filters],
  );

  const totalStock = useMemo(
    () => products.reduce((a, b) => a + (b.stock || 0), 0),
    [products],
  );

  return (
    <>
      <PromoBanner />
      <Hero filteredCount={filtered.length} totalStock={totalStock} />
      <div className="t-shop-body">
        <Filters
          filters={filters}
          setFilters={setFilters}
          categories={categories}
          filteredCount={filtered.length}
          totalCount={products.length}
          loading={loading}
          density={density}
          setDensity={setDensity}
        />
        <ProductGrid
          products={filtered}
          loading={loading}
          error={error}
          density={density}
          totalCount={products.length}
          onOpen={onOpenProduct}
          onAdd={onAddToCart}
          onReset={reset}
          onRetry={refetch}
        />
      </div>
    </>
  );
}
