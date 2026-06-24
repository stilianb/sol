interface StatusBarProps {
  stage: string;
  elapsed: number;
  lines?: string[];
}

function fmt(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  return `${(ms / 1000).toFixed(1)}s`;
}

export function StatusBar({ stage, elapsed, lines }: StatusBarProps) {
  if (!stage) return null;
  return (
    <div className="status-bar" role="status" aria-live="polite">
      <span className="status-stage">{stage}</span>
      <span className="status-elapsed">{fmt(elapsed)}</span>
      {lines && lines.length > 0 && (
        <ul className="status-lines">
          {lines.map((l, i) => <li key={i}>{l}</li>)}
        </ul>
      )}
    </div>
  );
}
