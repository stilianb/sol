import { describe, it, expect, vi } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { CrawlForm } from './CrawlForm';

describe('CrawlForm', () => {
  it('renders a URL input', () => {
    render(<CrawlForm onStart={vi.fn()} disabled={false} />);
    expect(screen.getByRole('textbox', { name: /url/i })).toBeInTheDocument();
  });

  it('calls onStart with url when submitted', () => {
    const onStart = vi.fn();
    render(<CrawlForm onStart={onStart} disabled={false} />);
    fireEvent.change(screen.getByRole('textbox', { name: /url/i }), { target: { value: 'https://example.com' } });
    fireEvent.submit(screen.getByRole('form'));
    expect(onStart).toHaveBeenCalledWith('https://example.com', expect.any(Object));
  });

  it('does not submit when url is empty', () => {
    const onStart = vi.fn();
    render(<CrawlForm onStart={onStart} disabled={false} />);
    fireEvent.submit(screen.getByRole('form'));
    expect(onStart).not.toHaveBeenCalled();
  });

  it('disables submit button when disabled=true', () => {
    render(<CrawlForm onStart={vi.fn()} disabled={true} />);
    expect(screen.getByRole('button', { name: /crawl/i })).toBeDisabled();
  });
});
