import { useState } from 'react';

interface CrawlFormProps {
  onStart: (url: string, opts: { depth: number; runners: number }) => void;
  disabled: boolean;
}

export function CrawlForm({ onStart, disabled }: CrawlFormProps) {
  const [url, setUrl] = useState('');
  const [depth, setDepth] = useState(2);
  const [runners, setRunners] = useState(4);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!url.trim()) return;
    onStart(url.trim(), { depth, runners });
  };

  return (
    <form onSubmit={handleSubmit} aria-label="Crawl form">
      <input
        type="text"
        value={url}
        onChange={e => setUrl(e.target.value)}
        placeholder="https://example.com"
        aria-label="URL"
      />
      <input type="number" value={depth} min={1} max={10} onChange={e => setDepth(Number(e.target.value))} aria-label="Depth" />
      <input type="number" value={runners} min={1} max={16} onChange={e => setRunners(Number(e.target.value))} aria-label="Runners" />
      <button type="submit" disabled={disabled}>Crawl</button>
    </form>
  );
}
