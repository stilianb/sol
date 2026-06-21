import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { renderHook, act } from '@testing-library/react';
import { useCrawlStream } from './useCrawlStream';

// Minimal EventSource mock
class MockEventSource {
  static instance: MockEventSource | null = null;
  url: string;
  onmessage: ((e: MessageEvent) => void) | null = null;
  listeners: Record<string, ((e: MessageEvent) => void)[]> = {};
  readyState = 0;

  constructor(url: string) {
    this.url = url;
    MockEventSource.instance = this;
    this.readyState = 1;
  }

  addEventListener(type: string, fn: (e: MessageEvent) => void) {
    this.listeners[type] = this.listeners[type] || [];
    this.listeners[type].push(fn);
  }

  removeEventListener(type: string, fn: (e: MessageEvent) => void) {
    this.listeners[type] = (this.listeners[type] || []).filter(f => f !== fn);
  }

  close() { this.readyState = 2; }

  emit(type: string, data: unknown) {
    const event = { data: JSON.stringify(data) } as MessageEvent;
    (this.listeners[type] || []).forEach(fn => fn(event));
  }
}

beforeEach(() => {
  MockEventSource.instance = null;
  vi.stubGlobal('EventSource', MockEventSource);
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('useCrawlStream', () => {
  it('starts idle with no runners or pages', () => {
    const { result } = renderHook(() => useCrawlStream());
    expect(result.current.runners).toEqual([]);
    expect(result.current.pages).toEqual([]);
    expect(result.current.done).toBeNull();
    expect(result.current.status).toBe('idle');
  });

  it('start() opens EventSource and sets status to running', () => {
    const { result } = renderHook(() => useCrawlStream());
    act(() => { result.current.start('https://example.com'); });
    expect(MockEventSource.instance).not.toBeNull();
    expect(MockEventSource.instance?.url).toContain('https%3A%2F%2Fexample.com');
    expect(result.current.status).toBe('running');
  });

  it('updates runners on progress event', () => {
    const { result } = renderHook(() => useCrawlStream());
    act(() => { result.current.start('https://example.com'); });
    act(() => {
      MockEventSource.instance!.emit('progress', {
        phase: 'round_start',
        total_done: 0,
        total_queued: 3,
        runners: [
          { id: 0, status: 'working', url: 'https://example.com', pages_done: 0, pages_failed: 0 },
          { id: 1, status: 'idle', url: '', pages_done: 0, pages_failed: 0 },
        ],
      });
    });
    expect(result.current.runners).toHaveLength(2);
    expect(result.current.runners[0].status).toBe('working');
    expect(result.current.runners[1].status).toBe('idle');
  });

  it('appends page on page event', () => {
    const { result } = renderHook(() => useCrawlStream());
    act(() => { result.current.start('https://example.com'); });
    act(() => {
      MockEventSource.instance!.emit('page', {
        url: 'https://example.com/about',
        status: 200,
        scores: { performance: 90, accessibility: 100, best_practices: 95, seo: 85, gdpr: 100, keyword: 80, aeo: 75 },
        findings: 3,
      });
    });
    expect(result.current.pages).toHaveLength(1);
    expect(result.current.pages[0].url).toBe('https://example.com/about');
    expect(result.current.pages[0].scores.performance).toBe(90);
  });

  it('sets done and status on done event', () => {
    const { result } = renderHook(() => useCrawlStream());
    act(() => { result.current.start('https://example.com'); });
    act(() => {
      MockEventSource.instance!.emit('done', {
        total_pages: 5, total_findings: 12, critical: 2, warning: 7, info: 3,
      });
    });
    expect(result.current.done).not.toBeNull();
    expect(result.current.done?.total_pages).toBe(5);
    expect(result.current.status).toBe('done');
  });

  it('stop() closes the stream and resets to idle', () => {
    const { result } = renderHook(() => useCrawlStream());
    act(() => { result.current.start('https://example.com'); });
    const es = MockEventSource.instance!;
    act(() => { result.current.stop(); });
    expect(es.readyState).toBe(2);
    expect(result.current.status).toBe('idle');
  });
});
