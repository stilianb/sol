import { describe, it, expect } from 'vitest';
import { parseSseEvent } from './sse';

describe('parseSseEvent', () => {
  it('parses progress event', () => {
    const data = JSON.stringify({
      phase: 'round_start',
      total_done: 2,
      total_queued: 5,
      runners: [{ id: 0, status: 'working', current_url: 'https://example.com', pages_done: 1, pages_failed: 0 }],
    });
    const ev = parseSseEvent('progress', data);
    expect(ev?.type).toBe('progress');
    if (ev?.type === 'progress') {
      expect(ev.data.phase).toBe('round_start');
      expect(ev.data.runners).toHaveLength(1);
      expect(ev.data.runners[0].status).toBe('working');
    }
  });

  it('parses page event', () => {
    const data = JSON.stringify({
      url: 'https://example.com/about',
      status: 200,
      scores: { performance: 90, accessibility: 100, best_practices: 95, seo: 85, gdpr: 100, keyword: 80, aeo: 75 },
      findings: 3,
    });
    const ev = parseSseEvent('page', data);
    expect(ev?.type).toBe('page');
    if (ev?.type === 'page') {
      expect(ev.data.url).toBe('https://example.com/about');
      expect(ev.data.scores.performance).toBe(90);
      expect(ev.data.findings).toBe(3);
    }
  });

  it('parses done event', () => {
    const data = JSON.stringify({ total_pages: 5, total_findings: 12, critical: 2, warning: 7, info: 3 });
    const ev = parseSseEvent('done', data);
    expect(ev?.type).toBe('done');
    if (ev?.type === 'done') {
      expect(ev.data.total_pages).toBe(5);
      expect(ev.data.critical).toBe(2);
    }
  });

  it('parses error event', () => {
    const data = JSON.stringify({ message: 'crawl failed: connection refused' });
    const ev = parseSseEvent('error', data);
    expect(ev?.type).toBe('error');
    if (ev?.type === 'error') {
      expect(ev.data.message).toContain('crawl failed');
    }
  });

  it('returns null for unknown event type', () => {
    expect(parseSseEvent('unknown', '{}')).toBeNull();
  });

  it('returns null for malformed JSON', () => {
    expect(parseSseEvent('page', 'not-json')).toBeNull();
  });
});
