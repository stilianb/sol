import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import { ScoreCard } from './ScoreCard';
import type { DoneEvent } from '../types/sse';

const summary: DoneEvent = { total_pages: 5, total_findings: 12, critical: 2, warning: 7, info: 3 };

describe('ScoreCard', () => {
  it('renders nothing when done is null', () => {
    const { container } = render(<ScoreCard done={null} />);
    expect(container.firstChild).toBeNull();
  });

  it('shows total pages', () => {
    render(<ScoreCard done={summary} />);
    expect(screen.getByText('5')).toBeInTheDocument();
  });

  it('shows critical count', () => {
    render(<ScoreCard done={summary} />);
    expect(screen.getByText('2')).toBeInTheDocument();
  });

  it('shows warning and info counts', () => {
    render(<ScoreCard done={summary} />);
    expect(screen.getByText('7')).toBeInTheDocument();
    expect(screen.getByText('3')).toBeInTheDocument();
  });

  it('shows total findings', () => {
    render(<ScoreCard done={summary} />);
    expect(screen.getByText('12')).toBeInTheDocument();
  });
});
