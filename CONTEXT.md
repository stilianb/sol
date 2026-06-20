# sol — Domain Glossary

## Audit

The process of fetching a URL and extracting structured data across five categories: performance, accessibility, best practices, SEO, and GDPR/cookies. An audit always targets a single page. A **crawl** is a multi-page audit.

## AuditReport

The structured output of a single-page audit. Contains all extracted data fields plus metadata (URL, HTTP status, fetch duration, active profile). Owned by the caller; must be `deinit`'d.

## DeviceProfile

One of three emulation contexts: `desktop`, `tablet`, or `mobile`. Determines the `profile=` suffix in the UA string and annotates timing results. Does not apply packet shaping — throttle figures are annotations only.

## AuditProfile

The combination of a `DeviceProfile` and a `gpu_accelerated` boolean passed into `audit.run()` and stored on `AuditReport`. The floor profile is `mobile` + `gpu_accelerated = false`. All scoring thresholds are validated against the floor first.

## Crawl

A multi-page audit: seeding from sitemap URLs, following internal links, deduplicating via a visited set, and auditing each reachable page up to a configured depth. Produces `[]AuditReport`.

## Frontier

The URL queue inside a crawl: a visited set (`StringHashMap`) for deduplication and a pending queue of URLs to fetch. URLs are added from sitemap seeds and discovered internal links.

## Finding

A single scored observation produced by the rules engine. Fields: `rule_id`, `category`, `severity` (`critical | warning | info`), `detail`. A page audit produces zero or more findings, one per violated rule.

## Rule

A named, stable check applied to an `AuditReport` to produce zero or one `Finding`. Identified by a `rule_id` (`<category>_<short_slug>`). Rules are documented in `docs/rules/<rule_id>.md`. Rule IDs never change once published — issues reference them.

## Score

A per-category integer 0–100. Computed as `100 − sum(penalties)`, floored at 0. Each rule contributes a fixed penalty when its finding fires. Scores are always computed against a specific `AuditProfile`. Categories: `performance`, `accessibility`, `best_practices`, `seo`, `gdpr`, `keyword`, `aeo`.

## Keyword Analysis

On-page keyword measurement extracted from static HTML. Includes: top 20 content words by frequency (stop words filtered), and — when a target keyword is given via `--keyword` — checks for presence in title, h1, and meta description, plus keyword density in per-mille (‰). Keyword rules fire only when a target keyword is provided; no live SERP data is used.

## AEO / GEO

Answer Engine Optimization and Generative Engine Optimization signals. Extracted from static HTML: structured data schema types (FAQPage, HowTo, Article), entity signals (author/publisher in ld+json or meta), Q&A content patterns (question-format headings), and outbound citation links. Scored as a single `aeo` category (0–100).

## Reproducibility

The guarantee that repeated runs of `sol` against the same HTML produce identical scores. All scoring inputs are derived from static HTML analysis only. `fetch_duration_ms` is recorded in `PerformanceData` for reporting but is never used in `score()`. This is an explicit invariant tested in `scorer.zig`.
