import { useState, useCallback, useEffect, useRef } from 'react';
import { API_BASE } from '../config';
import type { AuditResult } from '../types/audit';

export type CompareStatus = 'idle' | 'loading' | 'done' | 'error';

export interface CompareState {
  status: CompareStatus;
  results: AuditResult[];
  progress: string[];   // per-URL status label
  elapsed: number;
  error: string | null;
  run: (urls: string[], keyword?: string) => void;
  reset: () => void;
}

export function useCompareFetch(): CompareState {
  const [status, setStatus]     = useState<CompareStatus>('idle');
  const [results, setResults]   = useState<AuditResult[]>([]);
  const [progress, setProgress] = useState<string[]>([]);
  const [elapsed, setElapsed]   = useState(0);
  const [error, setError]       = useState<string | null>(null);
  const startRef                = useRef<number>(0);
  const timerRef                = useRef<ReturnType<typeof setInterval> | null>(null);

  const stopTimer = () => {
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }
  };

  const reset = useCallback(() => {
    stopTimer();
    setStatus('idle'); setResults([]); setProgress([]); setElapsed(0); setError(null);
  }, []);

  const run = useCallback((urls: string[], keyword?: string) => {
    const valid = urls.filter(u => u.trim());
    stopTimer();
    setStatus('loading'); setResults([]); setError(null); setElapsed(0);
    setProgress(valid.map(u => `${u} — fetching…`));
    startRef.current = Date.now();

    timerRef.current = setInterval(() => {
      setElapsed(Date.now() - startRef.current);
    }, 200);

    const fetches = valid.map((url, idx) => {
      const params = new URLSearchParams({ url });
      if (keyword) params.set('keyword', keyword);
      return window.fetch(`${API_BASE}/api/audit?${params}`)
        .then(res => {
          if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
          return res.json() as Promise<AuditResult>;
        })
        .then(data => {
          setProgress(prev => {
            const next = [...prev];
            next[idx] = `${url} — done`;
            return next;
          });
          return data;
        })
        .catch(err => {
          setProgress(prev => {
            const next = [...prev];
            next[idx] = `${url} — error`;
            return next;
          });
          throw err;
        });
    });

    Promise.all(fetches)
      .then(data => {
        stopTimer(); setElapsed(Date.now() - startRef.current);
        setResults(data); setStatus('done');
      })
      .catch(err => {
        stopTimer();
        setError(err instanceof Error ? err.message : 'Fetch failed');
        setStatus('error');
      });
  }, []);

  useEffect(() => () => stopTimer(), []);

  return { status, results, progress, elapsed, error, run, reset };
}
