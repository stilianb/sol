# sol — Website Audit Tool

SEMRush/Lighthouse-style site auditor built in Zig 0.16.0. Fetches URLs and extracts structured audit data across accessibility (WCAG 2.2), performance, SEO, best practices, and GDPR cookie compliance. Data collection now; scoring and issue tracking later.

## Usage

```
zig build
./zig-out/bin/sol <url>
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
- **TDD** — red-green-refactor throughout, 68 tests

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
  main.zig             — CLI entry point
  fetcher.zig          — HTTP fetch via std.http.Client; returns Response{status, body, duration_ms}
  audit.zig            — AuditReport aggregate; run() + renderText(); profile-aware
  parser/
    html.zig           — HtmlDoc wrapper: title, metaDescription, h1, links, classifiedLinks, headings
  crawler/
    robots.zig         — robots.txt parser: Rules{sitemaps, disallowed, allowed, crawl_delay_ms, isAllowed()}
    sitemap.zig        — XML sitemap parser: flat urlset + sitemapindex; candidateUrls()
  auditor/
    wcag.zig           — WCAG 2.2 data: lang, title, viewport, skip link, heading sequence, images, links, inputs, landmarks, tabindex
    performance.zig    — Perf data: timing, script/stylesheet breakdown, image dims, resource hints, third-party domains
    cookies.zig        — GDPR data: third-party scripts/iframes, tracker detection, consent banner detection
    seo.zig            — SEO data: title, description, canonical, meta robots, Open Graph, structured data presence (future)
    best_practices.zig — Best practices: HTTPS, mixed content, deprecated tags, redirect detection (future)
```

## Milestone status

- **M1** ✓ — fetch URL, print HTTP status + body_len
- **M2** ✓ — HTML parsing, robots.txt, sitemap discovery + audit data
- **M2+** ✓ — WCAG 2.2 data, performance stats, cookie/GDPR data extraction; shared helpers; architecture refactor; pushed to GitHub

## Milestones

### M3 — Full site crawler
URL queue/frontier (`StringHashMap` visited set), `Io.Group` concurrent fetches, respect `robots.isAllowed` before each fetch, sitemap URLs as seeds, follow internal links up to configurable depth. Produces `[]AuditReport` (one per page).

### M4 — Device profiles + audit profiles
Introduce `DeviceProfile` type (`desktop | tablet | mobile`) and `AuditProfile` (profile + gpu flag). Pass into `audit.run()`. Store in `AuditReport`. Fetcher sends matching `User-Agent` header. Timing annotated with profile. Enables per-profile comparison in M6.

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
JSON output (`renderJson`), CLI summary by severity. Issue records with `{url, category, rule_id, severity, detail}`. GitHub Issues integration (create issues via `gh` CLI or API). Future: Linear, Jira.

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
