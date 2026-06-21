import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { RunnerGrid } from './RunnerGrid';
import type { RunnerSnapshot } from '../types/sse';

const makeRunner = (overrides: Partial<RunnerSnapshot>): RunnerSnapshot => ({
  id: 0, status: 'idle', url: '', pages_done: 0, pages_failed: 0, ...overrides,
});

describe('RunnerGrid', () => {
  it('renders nothing when runners array is empty', () => {
    const { container } = render(<RunnerGrid runners={[]} />);
    expect(container.firstChild).toBeNull();
  });

  it('renders one card per runner', () => {
    const runners = [makeRunner({ id: 0 }), makeRunner({ id: 1 }), makeRunner({ id: 2 })];
    render(<RunnerGrid runners={runners} />);
    expect(screen.getAllByRole('article')).toHaveLength(3);
  });

  it('shows runner id on each card', () => {
    render(<RunnerGrid runners={[makeRunner({ id: 3 })]} />);
    expect(screen.getByText(/runner 3/i)).toBeInTheDocument();
  });

  it('shows status on each card', () => {
    render(<RunnerGrid runners={[makeRunner({ id: 0, status: 'working' })]} />);
    expect(screen.getByText('working')).toBeInTheDocument();
  });

  it('shows url when working', () => {
    render(<RunnerGrid runners={[makeRunner({ id: 0, status: 'working', url: 'https://example.com/page' })]} />);
    expect(screen.getByText('https://example.com/page')).toBeInTheDocument();
  });

  it('shows pages_done and pages_failed counts', () => {
    render(<RunnerGrid runners={[makeRunner({ id: 0, pages_done: 4, pages_failed: 1 })]} />);
    expect(screen.getByText('4')).toBeInTheDocument();
    expect(screen.getByText('1')).toBeInTheDocument();
  });
});
