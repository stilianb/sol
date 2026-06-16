# sol — Website Audit Tool

SEMRush-style site auditor built in Zig 0.16.0. Fetches a URL and extracts raw audit data across accessibility, performance, and GDPR cookie compliance. No scoring yet — data collection only.

## Usage

```
zig build
./zig-out/bin/sol <url>
```

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
  root.zig             — library root; re-exports all modules; test {} discovery block
  main.zig             — CLI entry point
  fetcher.zig          — HTTP fetch via std.http.Client; returns Response{status, body, duration_ms}
  parser/
    html.zig           — HtmlDoc wrapper: title, metaDescription, h1, links, classifiedLinks, headings
  crawler/
    robots.zig         — robots.txt parser: Rules{sitemaps, disallowed, allowed, crawl_delay_ms, isAllowed()}
    sitemap.zig        — XML sitemap parser: flat urlset + sitemapindex; candidateUrls()
  auditor/
    wcag.zig           — WCAG 2.2 data: lang, title, viewport, skip link, heading sequence, images, links, inputs, landmarks, tabindex
    performance.zig    — Perf data: timing, script/stylesheet breakdown, image dims, resource hints, third-party domains
    cookies.zig        — GDPR data: third-party scripts/iframes, tracker detection, consent banner detection
```

## Milestone status

- **M1** ✓ — fetch URL, print HTTP status + body_len
- **M2** ✓ — HTML parsing, robots.txt, sitemap discovery + audit data
- **M2+** ✓ — WCAG 2.2 data, performance stats, cookie/GDPR data extraction

## Next milestones

- **M3** — Full site crawler: URL queue, visited set (`StringHashMap`), `Io.Group` concurrency, respect `robots.isAllowed`; use sitemap URLs as seeds
- **M4** — Audit rules engine: score findings (broken links, duplicate titles, missing meta, redirect chains, heading order violations, WCAG failures)
- **M5** — Reporting: JSON output, CLI summary by severity

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
