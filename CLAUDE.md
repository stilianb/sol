# sol — Website Audit Tool

SEMRush/Lighthouse-style site auditor built in Zig 0.16.0. Fetches URLs and extracts structured audit data across accessibility (WCAG 2.2), performance, SEO, best practices, and GDPR cookie compliance. CLI tool + HTTP server for a webapp frontend.

## Usage

```
zig build
./zig-out/bin/sol <url>                        # CLI audit
./zig-out/bin/sol-server [--port 8080]         # HTTP server
zig build serve [-- --port 8080]               # run server directly
```

## Goals

Build a self-hosted, reproducible auditing engine that produces data equivalent to (or better than) Google Lighthouse across five audit categories:

| Category        | Scope                                                                 |
|-----------------|-----------------------------------------------------------------------|
| Performance     | Resource counts, render-blocking assets, image dims, resource hints, third-party load, HTML weight |
| Accessibility   | WCAG 2.2 AA: lang, headings, images, links, inputs, landmarks, tabindex, zoom |
| Best Practices  | HTTPS, mixed content, console errors, deprecated APIs, redirect chains |
| SEO             | Title, meta description, h1, canonical, robots directives, sitemap coverage |
| GDPR/Cookies    | Consent banner, third-party trackers, iframe origins, known consent tools |

**Consistency requirement**: all audits must be runnable under controlled, reproducible conditions — matching Lighthouse's emulated device profiles and network throttling. No live browser needed; emulation via request headers and static HTML analysis.

## Device + throttling profiles

Three profiles used for all scored runs:

| Profile  | Viewport      | UA hint                  | Throttle (down/up/RTT) |
|----------|---------------|--------------------------|------------------------|
| Desktop  | 1350×940      | desktop UA               | none / 40Mbps baseline |
| Tablet   | 768×1024      | tablet UA                | 10Mbps / 5Mbps / 40ms  |
| Mobile   | 375×667       | mobile UA                | 1.6Mbps / 750Kbps / 150ms |

Throttling is HTTP-level only (affects `fetcher.zig` timing). No packet shaping — we emulate by measuring raw fetch time and annotating results with the active profile.

GPU acceleration flag is a metadata annotation on the report (`gpu_accelerated: bool`). Not measurable from static HTML — caller sets it; defaults to `true` for desktop, `false` for mobile.

Profile passed into `audit.run()` and stored in `AuditReport`. All rendering and scoring must be profile-aware.

### Floor-first testing principle

**Always develop and validate against the lowest viable profile first**: Mobile + no GPU + 1.6Mbps throttle. If audit rules, thresholds, and rendering pass at the floor, the upper profiles follow cleanly. Never tune thresholds against desktop-only numbers — a site that scores well on mobile feels fast everywhere else.

Practical rule: every new audit rule must have a test fixture that represents realistic mobile HTML (lean DOM, minimal scripts). Desktop-only fixtures are only acceptable for rules that are explicitly desktop-scope.

## Tech

- **Zig 0.16.0** — new `main(init: std.process.Init)` signature, `init.io` / `init.gpa` / `init.arena`
- **libxml2** — HTML + XML parsing via C FFI (`htmlReadMemory`, `xmlReadMemory`, XPath)
- **TDD** — red-green-refactor throughout, 160 tests

### C FFI critical rule

Every file that uses libxml2 must import the shared cImport module:

```zig
const c = @import("../xml.zig").c;  // from src/auditor/ or src/crawler/
const c = @import("xml.zig").c;     // from src/parser/
```

**Never** do a local `@cImport` in individual files. Zig treats each `@cImport` as a distinct type namespace — two files with identical `@cImport` blocks produce incompatible `*xmlDoc` types, causing compile errors like "expected type '*cimport.struct__xmlDoc', found '*cimport.struct__xmlDoc'".

### Zig 0.16 patterns

```zig
// ArrayList — .empty init, allocator per-op
var list: std.ArrayList(T) = .empty;
list.append(allocator, val);
list.toOwnedSlice(allocator);

// trimEnd (not trimRight — renamed)
std.mem.trimEnd(u8, str, "/")

// Attribute existence — use xmlHasProp, not xmlGetProp
// xmlGetProp allocates; xmlHasProp returns *xmlAttr (no alloc)
const has_attr = c.xmlHasProp(node, "async") != null;
```

### Test discovery

Every new module must be added to the `test { ... }` block in `src/root.zig`:

```zig
test {
    _ = @import("fetcher.zig");
    _ = @import("parser/html.zig");
    _ = @import("crawler/robots.zig");
    _ = @import("crawler/sitemap.zig");
    _ = @import("auditor/wcag.zig");
    _ = @import("auditor/performance.zig");
    _ = @import("auditor/cookies.zig");
}
```

### Server module ownership rule

`server/router.zig` and `server/sse.zig` are part of the `sol` library module (exported from `root.zig`). The `sol-server` binary imports them **only through `@import("sol")`**, never via direct relative paths:

```zig
// handlers.zig — CORRECT
const sol = @import("sol");
const router = sol.server.router;
const sse = sol.server.sse;

// WRONG — causes "file exists in modules 'root' and 'sol'" compile error
const router = @import("router.zig");
```

Zig rejects a file that belongs to two modules simultaneously. Any new server module added to `root.zig` must follow this pattern.

### build.zig — linking libxml2

Applied to `mod` (Module), NOT `exe` (Compile):

```zig
mod.link_libc = true;
mod.linkSystemLibrary("xml2", .{});
mod.addIncludePath(.{ .cwd_relative = "/usr/include/libxml2" });
```

## Source layout

```
src/
  xml.zig              — shared @cImport for libxml2 (all files import from here)
  xml_helpers.zig      — shared node/xpath/URL helpers (extractHostname, getAttrText, hasAttr, etc.)
  root.zig             — library root; re-exports all modules; test {} discovery block
  main.zig             — CLI entry point (sol binary)
  fetcher.zig          — HTTP fetch via std.http.Client; returns Response{status, body, duration_ms}
  audit.zig            — AuditReport aggregate; run() + renderText/renderJson(); profile-aware
  parser/
    html.zig           — HtmlDoc wrapper: title, metaDescription, h1, links, classifiedLinks, headings
  crawler/
    robots.zig         — robots.txt parser: Rules{sitemaps, disallowed, allowed, crawl_delay_ms, isAllowed()}
    sitemap.zig        — XML sitemap parser: flat urlset + sitemapindex; candidateUrls()
    crawler.zig        — multi-page crawl with Frontier dedup and Io.Group concurrency
    pool.zig           — async runner pool: N named slots, ProgressFn/PageFn callbacks with ctx
  auditor/
    wcag.zig           — WCAG 2.2 data: lang, title, viewport, skip link, heading sequence, images, links, inputs, landmarks, tabindex
    performance.zig    — Perf data: timing, script/stylesheet breakdown, image dims, resource hints, third-party domains
    cookies.zig        — GDPR data: third-party scripts/iframes, tracker detection, consent banner detection
    seo.zig            — SEO data: title, description, canonical, meta robots, Open Graph, structured data presence
    best_practices.zig — Best practices: HTTPS, mixed content, deprecated tags, redirect detection
    keywords.zig       — Keyword frequency + target keyword coverage (density in per-mille)
    aeo.zig            — AEO/GEO signals: FAQ/HowTo/Article schema, author/publisher entities, Q&A headings, citations
    scorer.zig         — Rules engine: findings + 0–100 scores across 7 categories
  server/
    router.zig         — pure query-param parsing + route matching (part of sol module)
    sse.zig            — SSE event formatters: writeProgressEvent/writePageEvent/writeDoneEvent (part of sol module)
    handlers.zig       — dispatch + handleAudit + handleCrawl (imports router/sse through sol)
    main.zig           — sol-server entry point: TCP accept loop, --port flag
```

## Versioning

Versions track ship order, not milestone numbers. M3 is the first tagged release (`v0.1.0`); each subsequent milestone increments the minor digit. `v1.0.0` is the first stable release after M7 ships.

| Milestone | Version  |
|-----------|----------|
| M3        | `v0.1.0` |
| M4        | `v0.2.0` |
| M5        | `v0.3.0` |
| M6        | `v0.4.0` |
| M7        | `v0.5.0` |
| M8        | `v0.6.0` |
| stable    | `v1.0.0` |

- Bug fixes within a milestone increment the patch digit (`v0.1.1`, `v0.1.2`).
- `build.zig.zon` is the single source of truth. Bumped in the same commit as the release tag.
- Every release tagged `v<version>`. Tags are never moved or deleted.
- No CHANGELOG pre-1.0 — milestone issues serve as the changelog.

See `docs/adr/0002-versioning-scheme.md`.

## Milestone status

- **M1** ✓ — fetch URL, print HTTP status + body_len
- **M2** ✓ — HTML parsing, robots.txt, sitemap discovery + audit data
- **M2+** ✓ — WCAG 2.2 data, performance stats, cookie/GDPR data extraction; shared helpers; architecture refactor; pushed to GitHub
- **M3** ✓ — DeviceProfile, AuditProfile, honest bot UA. `v0.1.0`
- **M4** ✓ — full site crawler with Frontier dedup, Io.Group concurrency. `v0.2.0`
- **M5** ✓ — SEO + best practices auditors, redirect chain tracking. `v0.3.0`
- **M6** ✓ — rules engine + scoring, 17 rules across 5 categories. `v0.4.0`
- **M7** ✓ — JSON output, severity summary, GitHub Issues export. `v0.5.0`
- **M8** ✓ — keyword ranking/AEO scoring, reproducibility guarantee, async runner pool, HTTP server + SSE streaming. `v0.6.0` (in progress)

## Milestones

### M3 — Device profiles + audit profiles
Introduce `DeviceProfile` type (`desktop | tablet | mobile`) and `AuditProfile` (profile + gpu flag). Pass into `audit.run()`. Store in `AuditReport`. Fetcher sends honest bot UA: `sol/<version> (site auditor; https://github.com/stilianb/sol; profile=<name>)` — never a browser impersonation. Version read from build options at compile time. Timing annotated with active profile. Enables per-profile comparison in M6. Ships as `v0.1.0`.

### M4 — Full site crawler
URL queue/frontier (`StringHashMap` visited set), `Io.Group` concurrent fetches with concurrency cap (max 4 in-flight per domain) to avoid triggering abuse detection. Respect `robots.isAllowed` before each fetch and `crawl_delay_ms` between requests. Sitemap URLs as seeds, follow internal links up to configurable depth (`--depth` flag). Produces `[]AuditReport` (one per page). Requires M3. Ships as `v0.2.0`.

### M5 — SEO + best practices auditors
`auditor/seo.zig`: canonical tag, meta robots (`noindex`/`nofollow`), Open Graph tags, structured data presence (`application/ld+json`), title length, description length.
`auditor/best_practices.zig`: HTTPS enforcement, mixed-content detection (http:// resources on https:// page), deprecated HTML elements (`<font>`, `<center>`, `<marquee>`), redirect chain depth (via response status).

### M6 — Rules engine + scoring
Score findings per Lighthouse categories (0–100). Rules:
- Performance: render-blocking count, image missing dims, inline script bytes, third-party count
- Accessibility: missing alt, missing labels, positive tabindex, viewport zoom disabled, missing lang
- Best Practices: mixed content, deprecated tags, missing HTTPS
- SEO: missing title/description, missing canonical, `noindex` present, sitemap missing
- GDPR: no consent banner + trackers present = violation

Each finding has `severity: critical | warning | info`. Issue list feeds M7 issue tracker.

### M7 — Reporting + issue tracker integration
JSON output (`renderJson`), CLI summary by severity. Issue records with `{url, category, rule_id, severity, detail}`. GitHub Issues integration (create issues via `gh` CLI or API) — **opt-in only via `--publish-issues` flag**; no data leaves the machine by default. Deduplication: skip creating an issue if one with the same `rule_id` + URL is already open. No telemetry. Ships as `v0.5.0`. Begin CHANGELOG for 1.0.0 preparation.

### M8 — Keyword/AEO scoring + HTTP server + webapp frontend
Keyword analysis (`auditor/keywords.zig`): top-20 frequency, target keyword in title/h1/description, density in per-mille. AEO/GEO scoring (`auditor/aeo.zig`): FAQPage/HowTo/Article schema, author/publisher entities, Q&A headings, outbound citations. Reproducibility guarantee: `fetch_duration_ms` never used in scoring (tested invariant). Async runner pool (`crawler/pool.zig`) with `ProgressFn`/`PageFn` callbacks + `callback_ctx` for closure-free context. HTTP server (`sol-server`): `GET /api/audit` (JSON), `GET /api/crawl` (SSE stream — `event:progress` per round, `event:page` per completed page, `event:done` final aggregate). Frontend: Astro + shadcn/ui React islands consuming the SSE stream. Ships as `v0.6.0`.

**Webapp frontend plan** (in progress):
- Astro project at `web/` with React islands (`@astrojs/react`) and shadcn/ui
- `web/src/components/RunnerGrid.tsx` — consumes SSE, renders runner cards per `event:progress`
- `web/src/components/FindingsTable.tsx` — per-page findings with severity badges per `event:page`
- `web/src/components/ScoreCard.tsx` — 7-category score display
- Dev: Astro on `:4321`, proxy `/api/*` to `sol-server` on `:8080`
- Prod: `astro build` → `web/dist/` served as static files by `sol-server`

## Audit rule documentation standard

Every rule added in M6+ must have a corresponding entry in `docs/rules/<rule_id>.md`. This is the source of truth for client-facing explanations.

### File format

```markdown
# <rule_id>

**Category**: performance | accessibility | best_practices | seo | gdpr
**Severity**: critical | warning | info
**Profiles**: all | desktop | mobile | tablet   ← which profiles this rule is active on

## What we check

One sentence: what the auditor measures in the HTML.

## Why it matters

One or two sentences: user impact. No jargon. Written for a non-technical client.

## How the score is affected

Exact formula or threshold table. Example:

| Finding                        | Impact      |
|-------------------------------|-------------|
| 0 render-blocking scripts     | +0 penalty  |
| 1–2 render-blocking scripts   | −10 points  |
| 3+ render-blocking scripts    | −25 points  |

Scores are per-category (0–100). Category score = 100 − sum of penalties, floored at 0.

## How to fix

Short actionable guidance. Link to MDN or WCAG spec where relevant.

## Profile notes (optional)

Any threshold differences per device profile. E.g. mobile penalty is 2× desktop for render-blocking scripts.
```

### Rule ID convention

`<category>_<short_slug>` — all lowercase, underscores. Examples:
- `perf_render_blocking_scripts`
- `a11y_missing_image_alt`
- `seo_missing_canonical`
- `gdpr_no_consent_banner`
- `bp_mixed_content`

Rule IDs are stable identifiers — once published they never change (issues reference them).

## XPath namespace note

Sitemaps use default XML namespace (`xmlns="..."`). Standard XPath `//url` matches nothing. Use `local-name()`:

```zig
c.xmlXPathEvalExpression("//*[local-name()='url']", ctx)
```

## Memory ownership pattern

libxml2 strings must be freed with `c.xmlFree.?`, not `allocator.free`. Dupe immediately:

```zig
const raw = c.xmlNodeGetContent(node) orelse return null;
defer c.xmlFree.?(raw);
const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
return allocator.dupe(u8, text) catch null;
```

Empty slices returned from functions that are later `deinit`'d must be heap-allocated (`allocator.alloc(T, 0)`), not static (`&.{}`). Freeing a static slice crashes.

## Agent skills

### Issue tracker

Issues live in GitHub Issues (`github.com/stilianb/sol`). See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles with one override: `ready-for-agent` → `ready-to-implement`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context repo: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Conventions

- **No AI attribution in commit/PR/issue text.** Commit messages, PR titles, PR bodies, and issue descriptions must not mention Claude, AI agents, or automation. Do not include `Co-Authored-By: Claude` or similar trailers.
