import type { RunnerSnapshot, RunnerStatus } from '../types/sse';

const STATUS_LABEL: Record<RunnerStatus, string> = {
  idle: 'idle',
  working: 'working',
  done: 'done',
};

function RunnerCard({ runner }: { runner: RunnerSnapshot }) {
  return (
    <article data-status={runner.status}>
      <span>Runner {runner.id}</span>
      <span>{STATUS_LABEL[runner.status]}</span>
      {runner.url && <span>{runner.url}</span>}
      <span>{runner.pages_done}</span>
      <span>{runner.pages_failed}</span>
    </article>
  );
}

export function RunnerGrid({ runners }: { runners: RunnerSnapshot[] }) {
  if (runners.length === 0) return null;
  return (
    <div>
      {runners.map(r => <RunnerCard key={r.id} runner={r} />)}
    </div>
  );
}
