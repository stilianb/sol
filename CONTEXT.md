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

A per-category integer 0–100. Computed as `100 − sum(penalties)`, floored at 0. Each rule contributes a fixed penalty when its finding fires. Scores are always computed against a specific `AuditProfile`.
