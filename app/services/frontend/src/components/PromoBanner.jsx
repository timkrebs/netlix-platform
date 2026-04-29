import React from 'react';
import useFeatureFlags from '../hooks/useFeatureFlags.jsx';

export default function PromoBanner() {
  const flags = useFeatureFlags();
  if (!flags.showPromoBanner) return null;
  return (
    <div className="t-promo-banner" role="status">
      <span className="t-promo-banner-mark">▌</span>
      <span className="t-promo-banner-text">
        {flags.promoText || 'PROMO'}
      </span>
      <span className="t-promo-banner-meta">VAULT · KV/V2 · LIVE</span>
    </div>
  );
}
