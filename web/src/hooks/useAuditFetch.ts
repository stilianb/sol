import { useState, useCallback } from 'react';
import { API_BASE } from '../config';
import type { AuditResult } from '../types/audit';

export type AuditStatus = 'idle' | 'loading' | 'done' | 'error';

export interface AuditState {
  status: AuditStatus;
  result: AuditResult | null;
  error: string | null;
  fetch: (url: string, keyword?: string) => void;
  reset: () => void;
}

export function useAuditFetch(): AuditState {
  const [status, setStatus] = useState<AuditStatus>('idle');
  const [result, setResult] = useState<AuditResult | null>(null);
  const [error, setError] = useState<string | null>(null);

  const reset = useCallback(() => {
    setStatus('idle');
    setResult(null);
    setError(null);
  }, []);

  const fetch = useCallback((url: string, keyword?: string) => {
    setStatus('loading');
    setResult(null);
    setError(null);

    const params = new URLSearchParams({ url });
    if (keyword) params.set('keyword', keyword);

    window.fetch(`${API_BASE}/api/audit?${params}`)
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json() as Promise<AuditResult>;
      })
      .then(data => {
        setResult(data);
        setStatus('done');
      })
      .catch(err => {
        setError(err instanceof Error ? err.message : 'Fetch failed');
        setStatus('error');
      });
  }, []);

  return { status, result, error, fetch, reset };
}
