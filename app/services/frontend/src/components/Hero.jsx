import React from 'react';

function Stat({ k, v }) {
  return (
    <div className="t-stat">
      <div className="t-stat-k">{k}</div>
      <div className="t-stat-v">{v}</div>
    </div>
  );
}

export default function Hero({ filteredCount, totalStock }) {
  return (
    <section className="t-hero">
      <div className="t-hero-meta">
        <span>SS-26 · DROP 004</span>
        <span>{filteredCount} SKUs</span>
      </div>
      <h1 className="t-hero-title">
        Goods for people
        <br />
        <span style={{ color: 'var(--accent)' }}>who read the docs.</span>
      </h1>
      <p className="t-hero-sub">
        Uniform merchandise from Netlix. Cotton, ceramic, vinyl.
        Specced, tested, stocked in our warehouse in Rotterdam.
      </p>
      <div className="t-hero-stats">
        <Stat k="Units in stock" v={totalStock.toLocaleString()} />
        <Stat k="Lead time" v="3–5d" />
        <Stat k="Returns" v="30d" />
        <Stat k="Origin" v="NL" />
      </div>
    </section>
  );
}
