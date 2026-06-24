interface ScoreBadgeProps {
  label: string;
  value: number;
}

function scoreClass(v: number): string {
  if (v >= 80) return 'score-good';
  if (v >= 50) return 'score-warn';
  return 'score-poor';
}

export function ScoreBadge({ label, value }: ScoreBadgeProps) {
  return (
    <div className={`score-badge ${scoreClass(value)}`}>
      <span className="score-value">{value}</span>
      <span className="score-label">{label.replace(/_/g, ' ')}</span>
    </div>
  );
}

export function ScoreRow({ scores }: { scores: Record<string, number> }) {
  return (
    <div className="score-row">
      {Object.entries(scores).map(([k, v]) => (
        <ScoreBadge key={k} label={k} value={v} />
      ))}
    </div>
  );
}
