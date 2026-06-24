import { useState } from 'react';
import { useCrawlStream } from '../hooks/useCrawlStream';
import { useAuditFetch } from '../hooks/useAuditFetch';
import { useCompareFetch } from '../hooks/useCompareFetch';
import { AuditForm } from './AuditForm';
import { AuditResult } from './AuditResult';
import { CrawlForm } from './CrawlForm';
import { RunnerGrid } from './RunnerGrid';
import { FindingsTable } from './FindingsTable';
import { ScoreCard } from './ScoreCard';
import { CompareForm } from './CompareForm';
import { CompareTable } from './CompareTable';
import { FindingsList } from './FindingsList';
import { StatusBar } from './StatusBar';

type Mode = 'audit' | 'crawl' | 'compare';

function ModeTab({ mode, active, onSelect }: { mode: Mode; active: boolean; onSelect: (m: Mode) => void }) {
  return (
    <button role="tab" aria-selected={active} onClick={() => onSelect(mode)}>
      {mode.charAt(0).toUpperCase() + mode.slice(1)}
    </button>
  );
}

function fmt(ms: number) {
  return ms < 1000 ? `${ms}ms` : `${(ms / 1000).toFixed(1)}s`;
}

export function CrawlApp() {
  const [mode, setMode] = useState<Mode>('audit');
  const audit   = useAuditFetch();
  const crawl   = useCrawlStream();
  const compare = useCompareFetch();

  return (
    <main>
      <h1>sol</h1>

      <nav role="tablist">
        <ModeTab mode="audit"   active={mode === 'audit'}   onSelect={setMode} />
        <ModeTab mode="crawl"   active={mode === 'crawl'}   onSelect={setMode} />
        <ModeTab mode="compare" active={mode === 'compare'} onSelect={setMode} />
      </nav>

      {mode === 'audit' && (
        <section role="tabpanel">
          <AuditForm onSubmit={audit.fetch} disabled={audit.status === 'loading'} />
          {audit.status === 'loading' && (
            <StatusBar stage={audit.stage} elapsed={audit.elapsed} />
          )}
          {audit.status === 'done' && (
            <p className="status-done">Completed in {fmt(audit.elapsed)}</p>
          )}
          {audit.error && <p role="alert">{audit.error}</p>}
          {audit.result && <AuditResult result={audit.result} />}
        </section>
      )}

      {mode === 'crawl' && (
        <section role="tabpanel">
          <CrawlForm onStart={(url, opts) => crawl.start(url, opts)} disabled={crawl.status === 'running'} />
          {crawl.status === 'running' && (
            <>
              <StatusBar stage="Crawling…" elapsed={0} />
              <button onClick={crawl.stop}>Stop</button>
            </>
          )}
          {crawl.error && <p role="alert">{crawl.error}</p>}
          <RunnerGrid runners={crawl.runners} />
          <FindingsTable pages={crawl.pages} />
          <ScoreCard done={crawl.done} />
        </section>
      )}

      {mode === 'compare' && (
        <section role="tabpanel">
          <CompareForm onSubmit={compare.run} disabled={compare.status === 'loading'} />
          {compare.status === 'loading' && (
            <StatusBar
              stage="Auditing URLs…"
              elapsed={compare.elapsed}
              lines={compare.progress}
            />
          )}
          {compare.status === 'done' && (
            <p className="status-done">Completed in {fmt(compare.elapsed)}</p>
          )}
          {compare.error && <p role="alert">{compare.error}</p>}
          {compare.results.length > 0 && (
            <>
              <CompareTable results={compare.results} />
              {compare.results.map((r, i) => (
                <details key={i}>
                  <summary>{r.url} — findings ({r.findings.length})</summary>
                  <FindingsList url={r.url} findings={r.findings} />
                </details>
              ))}
            </>
          )}
        </section>
      )}
    </main>
  );
}
