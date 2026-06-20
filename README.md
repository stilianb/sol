# sol

A self-hosted website auditor built in Zig. Reproduces Lighthouse-style scoring across seven categories: performance, accessibility, best practices, SEO, GDPR, keyword coverage, and AEO/GEO signals — all from static HTML analysis, no browser required.

## Install

```sh
git clone https://github.com/stilianb/sol
cd sol
zig build
```

Binary is at `./zig-out/bin/sol`. Requires Zig 0.16 and libxml2 (`libxml2-dev` on Debian/Ubuntu, `libxml2` on Arch).

## Commands

### Single-page audit

```sh
sol <url>
```

Fetches the URL and prints a full audit report: WCAG, performance, SEO, GDPR, keyword, and AEO data, followed by a scored summary.

```sh
sol https://example.com
sol https://example.com --json
sol https://example.com --keyword "site audit tool"
sol https://example.com --keyword "site audit tool" --json
```

### Site crawl

```sh
sol <url> --depth <N>
```

Crawls the site up to `N` levels deep from the seed URL, following internal links and sitemap entries. Prints one report per page.

```sh
sol https://example.com --depth 2
sol https://example.com --depth 3 --json
sol https://example.com --depth 1 --keyword "your phrase"
```

### Publish findings to GitHub Issues

```sh
sol <url> --publish-issues
```

Creates a GitHub Issue for each finding. Requires the `gh` CLI to be authenticated. Deduplicates — skips issues that already exist for the same `rule_id` + URL. **Opt-in only; no data leaves the machine without this flag.**

```sh
sol https://example.com --publish-issues
sol https://example.com --depth 2 --publish-issues
```

## Flags

| Flag | Default | Description |
|---|---|---|
| `--keyword PHRASE` | — | Target keyword to score against (title, h1, description, density) |
| `--depth N` | 0 (single page) | Crawl depth; 0 = seed URL only |
| `--json` | off | Output JSON instead of plain text |
| `--publish-issues` | off | Create GitHub Issues for findings |

## Output

Plain text (default):

```
=== Page Audit: https://example.com ===
...

=== Scores ===
performance    = 95
accessibility  = 100
best_practices = 100
seo            = 85
gdpr           = 100
keyword        = 90
aeo            = 75

=== Summary ===
category            score  critical   warning  info
------------------  -----  --------   -------  ----
performance            95         0         0     0
...

=== Findings (3) ===
[warning] seo_missing_canonical: no canonical link element
[info]    aeo_no_citations: no outbound citation links found
[info]    kw_low_keyword_density: keyword density 2‰ is below 5‰ minimum
```

JSON (`--json`): one object per page with `url`, `status`, `scores`, and `findings` array.

## Scoring

Each category scores 0–100 using a penalty model: `score = 100 − sum(penalties)`, floored at 0. Scores are computed from static HTML only — network timing never affects them, so results are reproducible across runs.

| Category | What it measures |
|---|---|
| Performance | Render-blocking scripts, missing image dimensions, inline script size, third-party domains |
| Accessibility | WCAG 2.2 AA: lang, alt text, input labels, tabindex, viewport zoom |
| Best Practices | HTTPS, mixed content, deprecated HTML elements, redirect depth |
| SEO | Title, meta description, canonical, noindex, sitemap coverage |
| GDPR | Consent banner presence vs. known trackers |
| Keyword | Target keyword in title / h1 / description; keyword density (requires `--keyword`) |
| AEO | FAQ/HowTo/Article schema, author/publisher entities, Q&A headings, outbound citations |

### Findings

Each finding carries a `rule_id`, `category`, `severity` (`critical` / `warning` / `info`), and detail string. Rule IDs are stable — GitHub Issues reference them.

Example rules: `kw_target_missing_from_title`, `aeo_no_structured_schema`, `seo_missing_canonical`, `a11y_missing_image_alt`.

Full rule documentation: [`docs/rules/`](docs/rules/).

## Device profiles

Audits are annotated with a device profile. The CLI defaults to `desktop`. All scoring thresholds are validated against the mobile floor first.

| Profile | Viewport | Throttle |
|---|---|---|
| Desktop | 1350×940 | none |
| Tablet | 768×1024 | 10 Mbps / 40ms RTT |
| Mobile | 375×667 | 1.6 Mbps / 150ms RTT |

## Architecture

```
src/
  main.zig              CLI entry point
  audit.zig             AuditReport + run() + render*()
  fetcher.zig           HTTP fetch with honest bot UA
  parser/html.zig       HtmlDoc wrapper (title, h1, links, headings)
  crawler/
    crawler.zig         Multi-page crawl with Frontier dedup
    pool.zig            Async runner pool (N concurrent runners, progress events)
    robots.zig          robots.txt parser
    sitemap.zig         XML sitemap parser
  auditor/
    wcag.zig            WCAG 2.2 data extraction
    performance.zig     Perf metrics (scripts, images, third-party)
    cookies.zig         GDPR / tracker / consent banner detection
    seo.zig             SEO signals (canonical, OG, structured data)
    best_practices.zig  HTTPS, mixed content, deprecated tags
    keywords.zig        Keyword frequency + target keyword coverage
    aeo.zig             AEO/GEO signals (schema, entities, Q&A, citations)
    scorer.zig          Rules engine: findings + 0–100 scores
```

## Tests

```
zig build test
```

148 tests. All auditor modules have unit tests using lean mobile HTML fixtures, following the floor-first principle: if a rule passes on mobile, it passes everywhere.

## Versioning

| Milestone | Version |
|---|---|
| M7 (current) | v0.5.0 |
| stable | v1.0.0 |

See [`docs/adr/`](docs/adr/) for architecture decisions.
