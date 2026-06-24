import type { AuditResult } from '../types/audit';
import type { Scores } from '../types/sse';

const SCORE_KEYS: (keyof Scores)[] = [
  'performance', 'accessibility', 'best_practices', 'seo', 'gdpr', 'keyword', 'aeo',
];

function scoreClass(v: number): string {
  if (v >= 80) return 'score-good';
  if (v >= 50) return 'score-warn';
  return 'score-poor';
}

function shortUrl(url: string): string {
  try { return new URL(url).hostname; } catch { return url; }
}

export function CompareTable({ results }: { results: AuditResult[] }) {
  if (results.length === 0) return null;

  return (
    <div className="compare-table">
      <table>
        <thead>
          <tr>
            <th>Category</th>
            {results.map((r, i) => <th key={i}>{shortUrl(r.url)}</th>)}
          </tr>
        </thead>
        <tbody>
          {SCORE_KEYS.map(key => (
            <tr key={key}>
              <td>{key.replace(/_/g, ' ')}</td>
              {results.map((r, i) => (
                <td key={i} className={scoreClass(r.scores[key])}>
                  {r.scores[key]}
                </td>
              ))}
            </tr>
          ))}
          <tr>
            <td>findings</td>
            {results.map((r, i) => {
              const crit = r.findings.filter(f => f.severity === 'critical').length;
              const warn = r.findings.filter(f => f.severity === 'warning').length;
              return <td key={i}>{crit}c {warn}w</td>;
            })}
          </tr>
          {results.some(r => r.builtwith) && (
            <tr>
              <td>tech stack</td>
              {results.map((r, i) => (
                <td key={i}>{r.builtwith ? `${r.builtwith.length} detected` : '—'}</td>
              ))}
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
}
