import { useState } from 'react';

interface CompareFormProps {
  onSubmit: (urls: string[], keyword?: string) => void;
  disabled: boolean;
}

export function CompareForm({ onSubmit, disabled }: CompareFormProps) {
  const [urls, setUrls] = useState(['', '', '']);
  const [keyword, setKeyword] = useState('');

  const setUrl = (i: number, v: string) => {
    const next = [...urls];
    next[i] = v;
    setUrls(next);
  };

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const valid = urls.filter(u => u.trim());
    if (valid.length < 2) return;
    onSubmit(valid, keyword.trim() || undefined);
  };

  return (
    <form onSubmit={handleSubmit} aria-label="Compare form">
      <input type="text" value={urls[0]} onChange={e => setUrl(0, e.target.value)} placeholder="https://primary.com" aria-label="URL 1" />
      <input type="text" value={urls[1]} onChange={e => setUrl(1, e.target.value)} placeholder="https://competitor.com" aria-label="URL 2" />
      <input type="text" value={urls[2]} onChange={e => setUrl(2, e.target.value)} placeholder="https://competitor2.com (optional)" aria-label="URL 3" />
      <input type="text" value={keyword} onChange={e => setKeyword(e.target.value)} placeholder="target keyword (optional)" aria-label="Keyword" />
      <button type="submit" disabled={disabled}>Compare</button>
    </form>
  );
}
