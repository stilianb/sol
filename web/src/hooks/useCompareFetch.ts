import { useState, useCallback } from 'react';
import { API_BASE } from '../config';
import type { AuditResult } from '../types/audit';

export type CompareStatus = 'idle' | 'loading' | 'done' | 'error';

export interface CompareState {
  status: CompareStatus;
  results: AuditResult[];
  error: string | null;
  run: (urls: string[], keyword?: string) => void;
  reset: () => void;
}

export function useCompareFetch(): CompareState {
  const [status, setStatus] = useState<CompareStatus>('idle');
  const [results, setResults] = useState<AuditResult[]>([]);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setStatus('idle');
    setResults([]);
    setError(null);
  }, []);

  const run = useCallback((urls: string[], keyword?: string) => {
    setStatus('loading');
    setResults([]);
    setError(null);

    const fetches = urls.filter(u => u.trim()).map(url => {
      const params = new URLSearchParams({ url });
      if (keyword) params.set('keyword', keyword);
      return window.fetch(`${API_BASE}/api/audit?${params}`)
        .then(res => {
          if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
          return res.json() as Promise<AuditResult>;
        });
    });

    Promise.all(fetches)
      .then(data => { setResults(data); setStatus('done'); })
      .catch(err => {
        setError(err instanceof Error ? err.message : 'Fetch failed');
        setStatus('error');
      });
  }, []);

  return { status, results, error, run, reset };
}
