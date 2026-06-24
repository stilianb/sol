import type { AuditResult, TechEntry } from '../types/audit';
import { ScoreRow } from './ScoreBadge';
import { FindingsList } from './FindingsList';

function MetaRow({ label, value }: { label: string; value: React.ReactNode }) {
  return <tr><td>{label}</td><td>{value ?? '—'}</td></tr>;
}

function PsiSection({ psi }: { psi: NonNullable<AuditResult['psi']> }) {
  const cwv: Array<[string, number | null, string]> = [
    ['LCP', psi.lcp_ms, 'ms'],
    ['FCP', psi.fcp_ms, 'ms'],
    ['CLS', psi.cls_score, ''],
    ['TBT', psi.tbt_ms, 'ms'],
    ['Speed Index', psi.speed_index_ms, 'ms'],
    ['INP', psi.inp_ms, 'ms'],
  ];
  const lh: Array<[string, number | null]> = [
    ['Performance', psi.lighthouse_performance],
    ['Accessibility', psi.lighthouse_accessibility],
    ['Best Practices', psi.lighthouse_best_practices],
    ['SEO', psi.lighthouse_seo],
  ];
  return (
    <section>
      <h3>PageSpeed Insights <small>({psi.strategy})</small></h3>
      <table>
        <tbody>
          {cwv.map(([label, val, unit]) => val != null && (
            <tr key={label}><td>{label}</td><td>{val}{unit}</td></tr>
          ))}
          {lh.map(([label, val]) => val != null && (
            <tr key={label}><td>Lighthouse {label}</td><td>{val}</td></tr>
          ))}
        </tbody>
      </table>
    </section>
  );
}

function TechStackSection({ techs }: { techs: TechEntry[] }) {
  const byCategory = techs.reduce<Record<string, TechEntry[]>>((acc, t) => {
    const cat = t.category || t.tag || 'Other';
    (acc[cat] ??= []).push(t);
    return acc;
  }, {});

  return (
    <section>
      <h3>Tech Stack <small>({techs.length} technologies)</small></h3>
      <table>
        <tbody>
          {Object.entries(byCategory).sort(([a], [b]) => a.localeCompare(b)).map(([cat, entries]) => (
            <tr key={cat}>
              <td>{cat}</td>
              <td>{entries.map(e => e.name).join(', ')}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </section>
  );
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

      {result.builtwith && result.builtwith.length > 0 && (
        <TechStackSection techs={result.builtwith} />
      )}

      {result.psi && <PsiSection psi={result.psi} />}

      <section>
        <h3>Findings</h3>
        <FindingsList url={result.url} findings={findings} />
      </section>
    </div>
  );
}
