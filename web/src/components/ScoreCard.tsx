import type { DoneEvent } from '../types/sse';

export function ScoreCard({ done }: { done: DoneEvent | null }) {
  if (!done) return null;
  return (
    <div>
      <dl>
        <dt>Pages</dt><dd>{done.total_pages}</dd>
        <dt>Findings</dt><dd>{done.total_findings}</dd>
        <dt>Critical</dt><dd>{done.critical}</dd>
        <dt>Warning</dt><dd>{done.warning}</dd>
        <dt>Info</dt><dd>{done.info}</dd>
      </dl>
    </div>
  );
}
