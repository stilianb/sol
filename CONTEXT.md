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

## Runner Pool

A fixed-size set of N named runner slots (0..N-1, max 16) that process the URL frontier in batch rounds. Each round: fill slots from frontier → dispatch all via `Io.Group` → collect results → fire callbacks. Runners are persistent identities across rounds, not goroutines — Zig's cooperative IO means only one fiber runs at a time between IO suspensions, so shared state (frontier, reports slice) is safe to mutate between rounds without locking.

## ProgressEvent

Emitted twice per round: at `round_start` (all active slots show `.working` + current URL) and at `round_end` (counts updated, slots back to `.idle`). Carries `[]RunnerSnapshot`, `total_done`, `total_queued`. Used by the HTTP server to stream `event:progress` SSE events to the frontend for live runner visualization.

## PageFn / ProgressFn

Callback function pointers in `PoolOptions`. Both take `(ctx: ?*anyopaque, ...)` — the `callback_ctx` field is passed through as the first argument, enabling closure-like patterns without heap allocation. `PageFn` fires once per successfully audited page (pointer valid only during callback). `ProgressFn` fires per round phase.

## SSE Stream

The `GET /api/crawl` endpoint streams three event types while the crawl runs:
- `event:progress` — runner grid snapshot per round (from `ProgressFn`)
- `event:page` — per-page scores + finding count as each page completes (from `PageFn`)
- `event:done` — final aggregate: total pages, total findings, counts by severity

Formatted by `server/sse.zig`. Frontend consumes via browser `EventSource` API.

## HTTP Server

`sol-server` binary (`zig build serve [-- --port N]`). Single-threaded accept loop using `std.Io.net`. Routes: `GET /api/audit` (JSON response), `GET /api/crawl` (SSE stream), `GET /health`. CORS headers on all responses. `server/router.zig` handles pure query-param parsing; `server/handlers.zig` orchestrates audit/crawl calls and writes responses. Both `router.zig` and `sse.zig` belong to the `sol` library module — `handlers.zig` imports them via `sol.server.router` / `sol.server.sse`, never via direct relative path.
