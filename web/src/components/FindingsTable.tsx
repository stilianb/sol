import type { PageEvent } from '../types/sse';

const SCORE_KEYS = ['performance', 'accessibility', 'best_practices', 'seo', 'gdpr', 'keyword', 'aeo'] as const;

export function FindingsTable({ pages }: { pages: PageEvent[] }) {
  if (pages.length === 0) return <p>No pages crawled yet.</p>;

  return (
    <table>
      <thead>
        <tr>
          <th>URL</th>
          <th>Status</th>
          {SCORE_KEYS.map(k => <th key={k}>{k}</th>)}
          <th>Findings</th>
        </tr>
      </thead>
      <tbody>
        {pages.map((p, i) => (
          <tr key={i}>
            <td>{p.url}</td>
            <td>{p.status}</td>
            {SCORE_KEYS.map(k => <td key={k}>{p.scores[k]}</td>)}
            <td>{p.findings}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
