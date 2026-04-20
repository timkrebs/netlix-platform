import React, { useEffect, useState } from 'react';
import { api, getUser, setSession, clearSession } from './api.js';

function fmtPrice(cents) {
  return `$${(cents / 100).toFixed(2)}`;
}

export default function App() {
  const [user, setUser] = useState(getUser());
  const [view, setView] = useState('shop');

  function logout() {
    clearSession();
    setUser(null);
    setView('shop');
  }

  return (
    <div className="app">
      <header>
        <h1>Netlix Shop</h1>
        <nav>
          <button onClick={() => setView('shop')}>Shop</button>
          {user && <button onClick={() => setView('orders')}>My Orders</button>}
          {user ? (
            <>
              <span className="who">{user.email}</span>
              <button onClick={logout}>Log out</button>
            </>
          ) : (
            <button onClick={() => setView('login')}>Log in</button>
          )}
        </nav>
      </header>
      <main>
        {view === 'shop' && <Shop user={user} />}
        {view === 'login' && (
          <Login
            onAuth={(u) => {
              setUser(u);
              setView('shop');
            }}
          />
        )}
        {view === 'orders' && user && <Orders />}
      </main>
    </div>
  );
}

function Shop({ user }) {
  const [products, setProducts] = useState([]);
  const [cart, setCart] = useState({});
  const [error, setError] = useState('');
  const [confirmation, setConfirmation] = useState(null);

  useEffect(() => {
    api.listProducts().then(setProducts).catch((e) => setError(e.message));
  }, []);

  function addToCart(p) {
    setCart((c) => ({ ...c, [p.id]: (c[p.id] || 0) + 1 }));
  }

  function changeQty(pid, delta) {
    setCart((c) => {
      const next = { ...c };
      const n = (next[pid] || 0) + delta;
      if (n <= 0) delete next[pid];
      else next[pid] = n;
      return next;
    });
  }

  async function checkout() {
    setError('');
    const items = Object.entries(cart).map(([pid, qty]) => ({
      product_id: Number(pid),
      quantity: qty,
    }));
    if (items.length === 0) return;
    try {
      const order = await api.createOrder(items);
      setConfirmation(order);
      setCart({});
    } catch (e) {
      setError(e.message);
    }
  }

  const cartTotal = products
    .filter((p) => cart[p.id])
    .reduce((sum, p) => sum + p.price_cents * cart[p.id], 0);

  return (
    <div className="shop">
      <section className="products">
        {products.map((p) => (
          <article key={p.id} className="product">
            <h3>{p.title}</h3>
            <p className="desc">{p.description}</p>
            <p className="price">{fmtPrice(p.price_cents)}</p>
            <p className="stock">{p.stock} in stock</p>
            <button disabled={p.stock === 0} onClick={() => addToCart(p)}>
              Add to cart
            </button>
          </article>
        ))}
      </section>
      <aside className="cart">
        <h2>Cart</h2>
        {Object.keys(cart).length === 0 && <p>Empty.</p>}
        <ul>
          {products
            .filter((p) => cart[p.id])
            .map((p) => (
              <li key={p.id}>
                <span>{p.title}</span>
                <span className="qty">
                  <button onClick={() => changeQty(p.id, -1)}>-</button>
                  {cart[p.id]}
                  <button onClick={() => changeQty(p.id, 1)}>+</button>
                </span>
                <span>{fmtPrice(p.price_cents * cart[p.id])}</span>
              </li>
            ))}
        </ul>
        {Object.keys(cart).length > 0 && (
          <>
            <p className="total">Total: {fmtPrice(cartTotal)}</p>
            {user ? (
              <button onClick={checkout}>Place order</button>
            ) : (
              <p className="hint">Log in to place an order.</p>
            )}
          </>
        )}
        {error && <p className="error">{error}</p>}
        {confirmation && (
          <div className="confirmation">
            <p>Order #{confirmation.id} confirmed!</p>
            <p>Total: {fmtPrice(confirmation.total_cents)}</p>
          </div>
        )}
      </aside>
    </div>
  );
}

function Login({ onAuth }) {
  const [mode, setMode] = useState('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  async function submit(e) {
    e.preventDefault();
    setError('');
    try {
      const fn = mode === 'login' ? api.login : api.signup;
      const res = await fn(email, password);
      setSession(res.token, { id: res.user_id, email: res.email });
      onAuth({ id: res.user_id, email: res.email });
    } catch (err) {
      setError(err.message);
    }
  }

  return (
    <form className="auth" onSubmit={submit}>
      <h2>{mode === 'login' ? 'Log in' : 'Create account'}</h2>
      <label>
        Email
        <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" required />
      </label>
      <label>
        Password
        <input
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          type="password"
          minLength={8}
          required
        />
      </label>
      <button type="submit">{mode === 'login' ? 'Log in' : 'Sign up'}</button>
      <button
        type="button"
        className="link"
        onClick={() => setMode(mode === 'login' ? 'signup' : 'login')}
      >
        {mode === 'login' ? 'Need an account? Sign up' : 'Have an account? Log in'}
      </button>
      {error && <p className="error">{error}</p>}
    </form>
  );
}

function Orders() {
  const [orders, setOrders] = useState([]);
  const [error, setError] = useState('');
  useEffect(() => {
    api.listOrders().then(setOrders).catch((e) => setError(e.message));
  }, []);
  return (
    <div className="orders">
      <h2>Your orders</h2>
      {error && <p className="error">{error}</p>}
      {orders.length === 0 && !error && <p>No orders yet.</p>}
      <ul>
        {orders.map((o) => (
          <li key={o.id}>
            <strong>Order #{o.id}</strong> — {fmtPrice(o.total_cents)} ({o.status})
            <ul className="items">
              {o.items.map((it, idx) => (
                <li key={idx}>
                  product {it.product_id} × {it.quantity} @ {fmtPrice(it.price_cents)}
                </li>
              ))}
            </ul>
          </li>
        ))}
      </ul>
    </div>
  );
}
