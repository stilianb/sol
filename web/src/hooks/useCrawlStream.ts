import { useState, useRef, useCallback } from 'react';
import { parseSseEvent, type RunnerSnapshot, type PageEvent, type DoneEvent } from '../types/sse';
import { API_BASE } from '../config';

export type CrawlStatus = 'idle' | 'running' | 'done' | 'error';

export interface CrawlState {
  status: CrawlStatus;
  runners: RunnerSnapshot[];
  pages: PageEvent[];
  done: DoneEvent | null;
  error: string | null;
  start: (url: string, opts?: { depth?: number; runners?: number; keyword?: string }) => void;
  stop: () => void;
}

export function useCrawlStream(): CrawlState {
  const [status, setStatus] = useState<CrawlStatus>('idle');
  const [runners, setRunners] = useState<RunnerSnapshot[]>([]);
  const [pages, setPages] = useState<PageEvent[]>([]);
  const [done, setDone] = useState<DoneEvent | null>(null);
  const [error, setError] = useState<string | null>(null);
  const esRef = useRef<EventSource | null>(null);

  const stop = useCallback(() => {
    esRef.current?.close();
    esRef.current = null;
    setStatus('idle');
    setRunners([]);
    setPages([]);
    setDone(null);
    setError(null);
  }, []);

  const start = useCallback((url: string, opts: { depth?: number; runners?: number; keyword?: string } = {}) => {
    esRef.current?.close();

    const params = new URLSearchParams({ url });
    if (opts.depth != null) params.set('depth', String(opts.depth));
    if (opts.runners != null) params.set('runners', String(opts.runners));
    if (opts.keyword) params.set('keyword', opts.keyword);

    const es = new EventSource(`${API_BASE}/api/crawl?${params}`);
    esRef.current = es;
    setStatus('running');
    setRunners([]);
    setPages([]);
    setDone(null);
    setError(null);

    const handle = (type: string) => (e: MessageEvent) => {
      const ev = parseSseEvent(type, e.data);
      if (!ev) return;
      switch (ev.type) {
        case 'progress': setRunners(ev.data.runners); break;
        case 'page':     setPages(prev => [...prev, ev.data]); break;
        case 'done':     setDone(ev.data); setStatus('done'); es.close(); break;
        case 'error':    setError(ev.data.message); setStatus('error'); es.close(); break;
      }
    };

    es.addEventListener('progress', handle('progress'));
    es.addEventListener('page',     handle('page'));
    es.addEventListener('done',     handle('done'));
    es.addEventListener('error',    handle('error'));
  }, []);

  return { status, runners, pages, done, error, start, stop };
}
