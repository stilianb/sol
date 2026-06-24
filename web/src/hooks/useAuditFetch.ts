import { useState, useCallback, useEffect, useRef } from 'react';
import { API_BASE } from '../config';
import type { AuditResult } from '../types/audit';

export type AuditStatus = 'idle' | 'loading' | 'done' | 'error';

const STAGES: Array<{ after: number; label: string }> = [
  { after: 0,    label: 'Fetching page…' },
  { after: 1500, label: 'Parsing HTML…' },
  { after: 2500, label: 'Scoring…' },
  { after: 4000, label: 'Running PageSpeed Insights…' },
  { after: 8000, label: 'Still working…' },
];

export interface AuditState {
  status: AuditStatus;
  result: AuditResult | null;
  error: string | null;
  elapsed: number;
  stage: string;
  fetch: (url: string, keyword?: string) => void;
  reset: () => void;
}

export function useAuditFetch(): AuditState {
  const [status, setStatus]   = useState<AuditStatus>('idle');
  const [result, setResult]   = useState<AuditResult | null>(null);
  const [error, setError]     = useState<string | null>(null);
  const [elapsed, setElapsed] = useState(0);
  const [stage, setStage]     = useState('');
  const startRef              = useRef<number>(0);
  const timerRef              = useRef<ReturnType<typeof setInterval> | null>(null);

  const stopTimer = () => {
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }
  };

  const reset = useCallback(() => {
    stopTimer();
    setStatus('idle'); setResult(null); setError(null); setElapsed(0); setStage('');
  }, []);

  const fetch = useCallback((url: string, keyword?: string) => {
    stopTimer();
    setStatus('loading'); setResult(null); setError(null); setElapsed(0);
    setStage(STAGES[0].label);
    startRef.current = Date.now();

    timerRef.current = setInterval(() => {
      const ms = Date.now() - startRef.current;
      setElapsed(ms);
      const current = [...STAGES].reverse().find(s => ms >= s.after);
      if (current) setStage(current.label);
    }, 200);

    const params = new URLSearchParams({ url });
    if (keyword) params.set('keyword', keyword);

    window.fetch(`${API_BASE}/api/audit?${params}`)
      .then(res => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json() as Promise<AuditResult>;
      })
      .then(data => {
        stopTimer();
        setResult(data); setStatus('done'); setStage('Done');
        setElapsed(Date.now() - startRef.current);
      })
      .catch(err => {
        stopTimer();
        setError(err instanceof Error ? err.message : 'Fetch failed');
        setStatus('error'); setStage('');
      });
  }, []);

  useEffect(() => () => stopTimer(), []);

  return { status, result, error, elapsed, stage, fetch, reset };
}
