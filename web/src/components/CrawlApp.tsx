import { useCrawlStream } from '../hooks/useCrawlStream';
import { CrawlForm } from './CrawlForm';
import { RunnerGrid } from './RunnerGrid';
import { FindingsTable } from './FindingsTable';
import { ScoreCard } from './ScoreCard';

export function CrawlApp() {
  const { status, runners, pages, done, error, start, stop } = useCrawlStream();

  return (
    <main>
      <h1>sol</h1>
      <CrawlForm onStart={start} disabled={status === 'running'} />
      {status === 'running' && (
        <button onClick={stop}>Stop</button>
      )}
      {error && <p role="alert">{error}</p>}
      <RunnerGrid runners={runners} />
      <FindingsTable pages={pages} />
      <ScoreCard done={done} />
    </main>
  );
}
