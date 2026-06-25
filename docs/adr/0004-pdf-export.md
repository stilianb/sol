# ADR-0004: PDF Export Strategy

## Status
Planned — implementation pending

## Context
Retina generates formatted PDF reports via WeasyPrint. Sol needs equivalent output for client handoff.

## Decision

### Phase 1: HTML report (no external dep)
`GET /projects/:id/report.html` — sol-server renders a self-contained HTML report with inline CSS.
Browser print-to-PDF gives a usable output immediately. Zero dependencies.

### Phase 2: Server-side PDF
`GET /projects/:id/report.pdf` — sol-server shells out:
```zig
const result = try std.process.Child.run(.{
    .allocator = allocator,
    .argv = &.{ "wkhtmltopdf", "--quiet", "-", "/tmp/report-<id>.pdf" },
    .stdin_behavior = .Pipe,
});
```
Write HTML to stdin, read PDF from output file, stream to client.

`wkhtmltopdf` is a static binary, no display server needed, available on Linux/Mac. Falls back to HTML response if not found on PATH.

### Report sections
1. Cover: project name, primary URL, date, overall score
2. Score summary table: all 6 categories + analyst lenses
3. Critical findings (severity=critical, grouped by category)
4. Recommendations (4 quadrants: no-brainer, quick-win, growth-move, transformational)
5. Analyst observations (per lens)
6. Per-page breakdown (url, scores, finding count)
7. Appendix: full findings list

### HTML template
Generated in Zig as a string (no templating engine). CSS embedded inline.
Tailwind not used for PDF output — raw CSS only (print-safe: no dynamic classes).

## Consequences
- Phase 1 ships immediately, zero infra
- Phase 2 requires wkhtmltopdf on server PATH (add to Dockerfile)
- PDF fidelity depends on wkhtmltopdf CSS support (good for tables/text, limited for complex layouts)
