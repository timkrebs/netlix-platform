import React, { useEffect, useState } from 'react';
import { Routes, Route, Navigate, useNavigate, useLocation } from 'react-router-dom';
import { api, getUser, clearSession, onSessionExpired } from './api.js';
import Nav from './components/Nav.jsx';
import CartDrawer from './components/CartDrawer.jsx';
import CatalogPage from './pages/CatalogPage.jsx';
import CartPage from './pages/CartPage.jsx';
import CheckoutPage from './pages/CheckoutPage.jsx';
import PDPPage from './pages/PDPPage.jsx';
import LoginPage from './pages/LoginPage.jsx';
import OrdersPage from './pages/OrdersPage.jsx';
import useCart from './hooks/useCart.js';
import useProducts from './hooks/useProducts.js';
import { FeatureFlagsProvider } from './hooks/useFeatureFlags.jsx';

function pathToNav(pathname) {
  if (pathname === '/login') return 'login';
  if (pathname === '/orders') return 'orders';
  return 'shop';
}

export default function App() {
  const [user, setUser] = useState(getUser());
  const [bootstrapping, setBootstrapping] = useState(!!getUser());
  const [cartOpen, setCartOpen] = useState(false);
  const { cart, addToCart: addToCartBase, setQty, clear: clearCart, count } = useCart();
  const productsCtx = useProducts();
  const navigate = useNavigate();
  const location = useLocation();
  const view = pathToNav(location.pathname);

  function addToCart(product, qty = 1) {
    addToCartBase(product, qty);
    setCartOpen(true);
  }

  // Validate any persisted session against the server on mount. If the
  // token has expired, was revoked, or the user no longer exists, /me
  // 401s and our global handler clears localStorage — we then surface
  // the login screen instead of a stale "logged-in" UI.
  useEffect(() => {
    if (!user) return;
    api.me()
      .then((p) => setUser({ id: p.id, email: p.email }))
      .catch(() => setUser(null))
      .finally(() => setBootstrapping(false));
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // Global session-lost listener — fired by any 401 returned by the
  // API client (e.g. token expired mid-session).
  useEffect(() => onSessionExpired(() => setUser(null)), []);

  async function logout() {
    try { await api.logout(); } catch { /* fire-and-forget */ }
    clearSession();
    setUser(null);
    navigate('/');
  }

  function handleNavigate(next) {
    if (next === 'shop') navigate('/');
    else if (next === 'login') navigate('/login');
    else if (next === 'orders') navigate('/orders');
  }

  function openCart() { setCartOpen(true); }
  function openProduct(product) { navigate(`/p/${product.id}`); }

  function reorder(order) {
    for (const item of order.items || []) {
      addToCartBase({ id: item.product_id }, item.quantity);
    }
    navigate('/cart');
  }

  async function placeOrder() {
    if (!user) {
      navigate('/login');
      return { ok: false, needsAuth: true };
    }
    const items = Object.entries(cart).map(([pid, qty]) => ({
      product_id: Number(pid),
      quantity: qty,
    }));
    if (items.length === 0) return { ok: false, error: 'Cart is empty.' };
    try {
      const order = await api.createOrder(items);
      clearCart();
      navigate('/checkout', { state: { order, placedAt: Date.now() } });
      return { ok: true, order };
    } catch (e) {
      return { ok: false, error: e.message || 'Checkout failed.' };
    }
  }

  if (bootstrapping) {
    return (
      <FeatureFlagsProvider>
        <Nav view={view} onNavigate={handleNavigate} cartCount={count} onOpenCart={openCart} />
        <section className="t-page">
          <div className="t-page-empty">
            <div className="t-loading" style={{ margin: 0, fontSize: 14 }}>SYNC…</div>
          </div>
        </section>
      </FeatureFlagsProvider>
    );
  }

  return (
    <FeatureFlagsProvider>
      <Nav view={view} onNavigate={handleNavigate} cartCount={count} onOpenCart={openCart} />
      {user && (
        <div className="t-user-bar">
          <span>{user.email}</span>
          <button type="button" className="t-link" onClick={logout}>LOG OUT</button>
        </div>
      )}
      <Routes>
        <Route
          path="/"
          element={
            <CatalogPage
              products={productsCtx.products}
              loading={productsCtx.loading}
              error={productsCtx.error}
              refetch={productsCtx.refetch}
              onOpenProduct={openProduct}
              onAddToCart={addToCart}
            />
          }
        />
        <Route
          path="/p/:id"
          element={
            <PDPPage
              products={productsCtx.products}
              loading={productsCtx.loading}
              error={productsCtx.error}
              refetch={productsCtx.refetch}
              onAddToCart={addToCart}
            />
          }
        />
        <Route
          path="/cart"
          element={
            <CartPage
              cart={cart}
              products={productsCtx.products}
              productsLoading={productsCtx.loading}
              setQty={setQty}
              onCheckout={placeOrder}
            />
          }
        />
        <Route path="/checkout" element={<CheckoutPage />} />
        <Route
          path="/login"
          element={
            user
              ? <Navigate to="/" replace />
              : <LoginPage onAuth={setUser} />
          }
        />
        <Route
          path="/orders"
          element={
            user
              ? (
                <OrdersPage
                  userEmail={user.email}
                  products={productsCtx.products}
                  onReorder={reorder}
                />
              )
              : <Navigate to="/login" replace />
          }
        />
      </Routes>
      <CartDrawer
        open={cartOpen}
        onClose={() => setCartOpen(false)}
        cart={cart}
        products={productsCtx.products}
        productsLoading={productsCtx.loading}
        setQty={setQty}
      />
    </FeatureFlagsProvider>
  );
}

