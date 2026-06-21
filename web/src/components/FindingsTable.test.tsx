import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { FindingsTable } from './FindingsTable';
import type { PageEvent } from '../types/sse';

const makePage = (overrides: Partial<PageEvent>): PageEvent => ({
  url: 'https://example.com',
  status: 200,
  scores: { performance: 90, accessibility: 100, best_practices: 95, seo: 85, gdpr: 100, keyword: 80, aeo: 75 },
  findings: 0,
  ...overrides,
});

describe('FindingsTable', () => {
  it('renders empty state when no pages', () => {
    render(<FindingsTable pages={[]} />);
    expect(screen.getByText(/no pages/i)).toBeInTheDocument();
  });

  it('renders a row per page', () => {
    const pages = [makePage({ url: 'https://a.com' }), makePage({ url: 'https://b.com' })];
    render(<FindingsTable pages={pages} />);
    expect(screen.getByText('https://a.com')).toBeInTheDocument();
    expect(screen.getByText('https://b.com')).toBeInTheDocument();
  });

  it('shows all 7 score categories', () => {
    render(<FindingsTable pages={[makePage({})]} />);
    expect(screen.getByText(/performance/i)).toBeInTheDocument();
    expect(screen.getByText(/accessibility/i)).toBeInTheDocument();
    expect(screen.getByText(/seo/i)).toBeInTheDocument();
    expect(screen.getByText(/gdpr/i)).toBeInTheDocument();
  });

  it('shows http status', () => {
    render(<FindingsTable pages={[makePage({ status: 404 })]} />);
    expect(screen.getByText('404')).toBeInTheDocument();
  });

  it('shows findings count', () => {
    render(<FindingsTable pages={[makePage({ findings: 7 })]} />);
    expect(screen.getByText('7')).toBeInTheDocument();
  });
});
