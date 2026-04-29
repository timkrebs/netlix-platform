import React, {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from 'react';

// Feature flags are sourced from /api/flags, which the gateway serves
// from a VSO-projected file backed by Vault KVv2. Polling (not push)
// because the propagation chain (Vault → VSO → Secret → kubelet → file
// → /api/flags) takes 30–90s and a cheap interval is good enough.
//
// Polling pauses while the tab is hidden — halves load when the demo
// is in a background tab.

const POLL_MS = 10_000;

const DEFAULT_FLAGS = Object.freeze({
  showPromoBanner: false,
  promoText: '',
});

const FeatureFlagsContext = createContext(DEFAULT_FLAGS);

export function FeatureFlagsProvider({ children }) {
  const [flags, setFlags] = useState(DEFAULT_FLAGS);
  const inFlightRef = useRef(false);

  useEffect(() => {
    let cancelled = false;

    async function fetchFlags() {
      if (inFlightRef.current) return;
      inFlightRef.current = true;
      try {
        const res = await fetch('/api/flags', { credentials: 'omit' });
        if (!res.ok) return;
        const data = await res.json();
        if (cancelled || !data || typeof data !== 'object') return;
        setFlags({
          showPromoBanner: !!data.showPromoBanner,
          promoText: typeof data.promoText === 'string' ? data.promoText : '',
        });
      } catch {
        // Network blip / bad JSON — keep last known good values.
      } finally {
        inFlightRef.current = false;
      }
    }

    fetchFlags();
    let timer = setInterval(fetchFlags, POLL_MS);

    function onVisibility() {
      if (document.visibilityState === 'hidden') {
        clearInterval(timer);
        timer = null;
      } else if (timer === null) {
        fetchFlags();
        timer = setInterval(fetchFlags, POLL_MS);
      }
    }
    document.addEventListener('visibilitychange', onVisibility);

    return () => {
      cancelled = true;
      if (timer) clearInterval(timer);
      document.removeEventListener('visibilitychange', onVisibility);
    };
  }, []);

  return (
    <FeatureFlagsContext.Provider value={flags}>
      {children}
    </FeatureFlagsContext.Provider>
  );
}

export default function useFeatureFlags() {
  return useContext(FeatureFlagsContext);
}
