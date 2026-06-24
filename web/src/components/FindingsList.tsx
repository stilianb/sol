import type { Finding } from '../types/audit';

function exportCsv(url: string, findings: Finding[]) {
  const rows = [
    'url,rule_id,category,severity,detail',
    ...findings.map(f => {
      const detail = f.detail.includes(',') || f.detail.includes('"')
        ? `"${f.detail.replace(/"/g, '""')}"` : f.detail;
      return `${url},${f.rule_id},${f.category},${f.severity},${detail}`;
    }),
  ];
  const blob = new Blob([rows.join('\n')], { type: 'text/csv' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'findings.csv';
  a.click();
}

export function FindingsList({ url, findings }: { url: string; findings: Finding[] }) {
  if (findings.length === 0) return <p>No findings.</p>;

  const critical = findings.filter(f => f.severity === 'critical');
  const warning  = findings.filter(f => f.severity === 'warning');
  const info     = findings.filter(f => f.severity === 'info');

  return (
    <div className="findings-list">
      <div className="findings-header">
        <span>{critical.length} critical</span>
        <span>{warning.length} warning</span>
        <span>{info.length} info</span>
        <button onClick={() => exportCsv(url, findings)}>Export CSV</button>
      </div>
      <table>
        <thead>
          <tr>
            <th>Severity</th>
            <th>Category</th>
            <th>Rule</th>
            <th>Detail</th>
          </tr>
        </thead>
        <tbody>
          {findings.map((f, i) => (
            <tr key={i} data-severity={f.severity}>
              <td>{f.severity}</td>
              <td>{f.category}</td>
              <td>{f.rule_id}</td>
              <td>{f.detail}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
