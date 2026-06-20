# sol

A self-hosted website auditor built in Zig. Reproduces Lighthouse-style scoring across seven categories: performance, accessibility, best practices, SEO, GDPR, keyword coverage, and AEO/GEO signals — all from static HTML analysis, no browser required.

## Install

```
zig build
```

Requires Zig 0.16 and libxml2.

## Usage

```
sol <url> [options]
```

| Flag | Description |
|---|---|
| `--keyword PHRASE` | Target keyword phrase to score against (title, h1, description, density) |
| `--depth N` | Crawl up to N levels deep (default: single page) |
| `--json` | Output JSON instead of plain text |
| `--publish-issues` | Create GitHub Issues for findings (requires `gh` CLI, opt-in) |

### Examples

```sh
# Audit a single page
sol https://example.com

# Audit with a target keyword
sol https://example.com --keyword "site audit tool"

# Crawl the whole site, output JSON
sol https://example.com --depth 3 --json
```

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

142 tests. All auditor modules have unit tests using lean mobile HTML fixtures, following the floor-first principle: if a rule passes on mobile, it passes everywhere.

## Versioning

| Milestone | Version |
|---|---|
| M7 (current) | v0.5.0 |
| stable | v1.0.0 |

See [`docs/adr/`](docs/adr/) for architecture decisions.
