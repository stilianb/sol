import { useState } from 'react';

interface AuditFormProps {
  onSubmit: (url: string, keyword?: string) => void;
  disabled: boolean;
}

export function AuditForm({ onSubmit, disabled }: AuditFormProps) {
  const [url, setUrl] = useState('');
  const [keyword, setKeyword] = useState('');

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!url.trim()) return;
    onSubmit(url.trim(), keyword.trim() || undefined);
  };

  return (
    <form onSubmit={handleSubmit} aria-label="Audit form">
      <input
        type="text"
        value={url}
        onChange={e => setUrl(e.target.value)}
        placeholder="https://example.com/page"
        aria-label="URL"
      />
      <input
        type="text"
        value={keyword}
        onChange={e => setKeyword(e.target.value)}
        placeholder="target keyword (optional)"
        aria-label="Keyword"
      />
      <button type="submit" disabled={disabled}>Audit</button>
    </form>
  );
}
