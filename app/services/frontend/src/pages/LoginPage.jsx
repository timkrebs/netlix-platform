import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, setSession } from '../api.js';

export default function LoginPage({ onAuth }) {
  const [mode, setMode] = useState('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(true);
  const [error, setError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const navigate = useNavigate();

  async function submit(e) {
    e.preventDefault();
    setError('');
    setSubmitting(true);
    try {
      const fn = mode === 'login' ? api.login : api.signup;
      const res = await fn(email, password);
      setSession(res.token, { id: res.user_id, email: res.email });
      onAuth?.({ id: res.user_id, email: res.email });
      navigate('/');
    } catch (err) {
      setError(err.message || 'Something went wrong.');
    } finally {
      setSubmitting(false);
    }
  }

  function switchMode(next) {
    setMode(next);
    setError('');
  }

  const submitLabel = submitting
    ? '…'
    : mode === 'login'
      ? 'CONTINUE →'
      : 'CREATE ACCOUNT →';

  return (
    <section className="t-page">
      <div className="t-auth">
        <div className="t-auth-side">
          <div className="t-auth-kicker">
            /{mode === 'login' ? 'session/new' : 'account/new'}
          </div>
          <h1 className="t-auth-title">
            {mode === 'login' ? 'Log in to continue.' : 'Create an account.'}
          </h1>
          <p className="t-auth-sub">
            A Netlix account gets you order history, faster checkout, and
            early access to drops. No marketing spam. Opt-in only.
          </p>
          <ul className="t-auth-bullets">
            <li><span>✓</span> JWT session, 24h TTL</li>
            <li><span>✓</span> Password: 10+ chars, 3/4 classes</li>
            <li><span>✓</span> We store nothing we don't need</li>
          </ul>
        </div>

        <form className="t-auth-form" onSubmit={submit} noValidate={false}>
          <div className="t-auth-tabs">
            <button
              type="button"
              className={mode === 'login' ? 'is-on' : ''}
              onClick={() => switchMode('login')}
              aria-pressed={mode === 'login'}
            >
              LOG IN
            </button>
            <button
              type="button"
              className={mode === 'signup' ? 'is-on' : ''}
              onClick={() => switchMode('signup')}
              aria-pressed={mode === 'signup'}
            >
              SIGN UP
            </button>
          </div>

          <label className="t-field">
            <span>EMAIL</span>
            <input
              type="email"
              placeholder="you@domain.com"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </label>

          <label className="t-field">
            <span>PASSWORD</span>
            <input
              type="password"
              placeholder="••••••••••"
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              minLength={mode === 'signup' ? 10 : 1}
              required
            />
            {mode === 'signup' && (
              <small>10+ chars, at least three of: upper, lower, digit, symbol.</small>
            )}
          </label>

          {mode === 'login' && (
            <div className="t-auth-row">
              <label className="t-check">
                <input
                  type="checkbox"
                  checked={remember}
                  onChange={(e) => setRemember(e.target.checked)}
                />{' '}
                <span>Remember this device</span>
              </label>
              <a className="t-link" href="#" onClick={(e) => e.preventDefault()}>
                Forgot password →
              </a>
            </div>
          )}

          {error && (
            <div
              role="alert"
              style={{
                fontFamily: 'var(--font-mono)',
                fontSize: 11,
                color: 'var(--warn)',
                letterSpacing: '0.04em',
              }}
            >
              {error}
            </div>
          )}

          <button className="t-btn-primary" type="submit" disabled={submitting}>
            {submitLabel}
          </button>

          <div className="t-auth-foot">
            <span>
              {mode === 'login' ? 'Not registered?' : 'Already have an account?'}
            </span>
            <button
              type="button"
              className="t-link"
              onClick={() => switchMode(mode === 'login' ? 'signup' : 'login')}
            >
              {mode === 'login' ? 'Create account' : 'Log in'}
            </button>
          </div>
        </form>
      </div>
    </section>
  );
}
