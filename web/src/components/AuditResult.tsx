import type { AuditResult } from '../types/audit';
import { ScoreRow } from './ScoreBadge';
import { FindingsList } from './FindingsList';

function MetaRow({ label, value }: { label: string; value: React.ReactNode }) {
  return <tr><td>{label}</td><td>{value ?? '—'}</td></tr>;
}

export function AuditResult({ result }: { result: AuditResult }) {
  const { scores, findings, keyword_analysis: kw, aeo_data: aeo } = result;

  return (
    <div className="audit-result">
      <h2>{result.url}</h2>

      <ScoreRow scores={scores} />

      <section>
        <h3>Page</h3>
        <table>
          <tbody>
            <MetaRow label="Status" value={result.status} />
            <MetaRow label="Title" value={result.title} />
            <MetaRow label="Description" value={result.description} />
            <MetaRow label="H1" value={result.h1} />
            <MetaRow label="Links" value={`${result.internal_links} internal / ${result.external_links} external`} />
            <MetaRow label="Hreflang" value={result.hreflang_count > 0 ? `${result.hreflang_count} tags` : 'none'} />
            <MetaRow label="Robots" value={result.has_robots ? 'found' : 'missing'} />
            <MetaRow label="Sitemap" value={result.sitemap_url ?? 'not found'} />
          </tbody>
        </table>
      </section>

      {kw.target_keyword && (
        <section>
          <h3>Keyword: {kw.target_keyword}</h3>
          <table>
            <tbody>
              <MetaRow label="In title" value={kw.in_title ? '✓' : '✗'} />
              <MetaRow label="In H1" value={kw.in_h1 ? '✓' : '✗'} />
              <MetaRow label="In description" value={kw.in_description ? '✓' : '✗'} />
              <MetaRow label="Density" value={`${kw.density_permille}‰`} />
              <MetaRow label="Total words" value={kw.total_words} />
            </tbody>
          </table>
        </section>
      )}

      <section>
        <h3>AEO signals</h3>
        <table>
          <tbody>
            <MetaRow label="FAQ schema" value={aeo.has_faq_schema ? '✓' : '—'} />
            <MetaRow label="HowTo schema" value={aeo.has_howto_schema ? '✓' : '—'} />
            <MetaRow label="Article schema" value={aeo.has_article_schema ? '✓' : '—'} />
            <MetaRow label="Author entity" value={aeo.has_author_entity ? '✓' : '—'} />
            <MetaRow label="Q&A headings" value={aeo.has_qa_headings ? '✓' : '—'} />
            <MetaRow label="Outbound links" value={aeo.outbound_link_count} />
          </tbody>
        </table>
      </section>

      <section>
        <h3>Findings</h3>
        <FindingsList url={result.url} findings={findings} />
      </section>
    </div>
  );
}
