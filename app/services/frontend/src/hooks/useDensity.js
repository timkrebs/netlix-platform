import { useEffect, useState } from 'react';

const STORAGE_KEY = 'netlix_density';
const VALID = new Set(['spacious', 'compact']);

function load() {
  try {
    const v = localStorage.getItem(STORAGE_KEY);
    return VALID.has(v) ? v : 'spacious';
  } catch {
    return 'spacious';
  }
}

export default function useDensity() {
  const [density, setDensityRaw] = useState(load);

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, density);
    } catch { /* quota/disabled — tolerate */ }
  }, [density]);

  function setDensity(next) {
    if (VALID.has(next)) setDensityRaw(next);
  }

  return { density, setDensity };
}
