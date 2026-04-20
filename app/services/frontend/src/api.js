// API client for the netlix shop. All non-auth handlers send the JWT
// from localStorage as a Bearer header. A 401 anywhere triggers a
// session wipe so the UI re-renders the login screen instead of
// silently leaving stale "logged-in" state in place.

const TOKEN_KEY = 'netlix_token';
const USER_KEY = 'netlix_user';

const onAuthLost = new Set();
export function onSessionExpired(fn) {
  onAuthLost.add(fn);
  return () => onAuthLost.delete(fn);
}
function fireAuthLost() {
  for (const fn of onAuthLost) fn();
}

export function getToken() {
  return localStorage.getItem(TOKEN_KEY);
}
export function getUser() {
  const v = localStorage.getItem(USER_KEY);
  return v ? JSON.parse(v) : null;
}
export function setSession(token, user) {
  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
}
export function clearSession() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

// Canonical request wrapper. Reads the JSON body, extracts the
// {error: {code, message}} format the auth service returns, and
// surfaces a clean Error to callers.
async function request(path, opts = {}) {
  const headers = { 'Content-Type': 'application/json', ...(opts.headers || {}) };
  const token = getToken();
  if (token && !opts.skipAuth) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(path, { ...opts, headers });
  const text = await res.text();
  const body = text ? safeJSON(text) : null;

  if (res.status === 401 && token) {
    clearSession();
    fireAuthLost();
  }
  if (!res.ok) {
    const msg = body?.error?.message || body?.error || `request failed: ${res.status}`;
    const err = new Error(msg);
    err.code = body?.error?.code;
    err.status = res.status;
    throw err;
  }
  return body;
}

function safeJSON(s) {
  try { return JSON.parse(s); } catch { return null; }
}

export const api = {
  // Auth
  signup: (email, password) =>
    request('/api/auth/signup', { method: 'POST', body: JSON.stringify({ email, password }), skipAuth: true }),
  login: (email, password) =>
    request('/api/auth/login', { method: 'POST', body: JSON.stringify({ email, password }), skipAuth: true }),
  logout: () =>
    request('/api/auth/logout', { method: 'POST' }),
  me: () =>
    request('/api/auth/me'),

  // Catalog
  listProducts: () => request('/api/catalog/products'),

  // Orders
  createOrder: (items) =>
    request('/api/orders/orders', { method: 'POST', body: JSON.stringify({ items }) }),
  listOrders: () => request('/api/orders/orders'),
};
