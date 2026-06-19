# seo_missing_canonical

**Category**: seo
**Severity**: info
**Profiles**: all

## What we check

Checks whether the page has a `<link rel="canonical" href="...">` element.

## Why it matters

Without a canonical tag, search engines may index multiple versions of the same URL (with/without trailing slash, HTTP vs HTTPS, www vs non-www) as separate pages, splitting ranking signals.

## How the score is affected

| Finding               | Penalty   |
|-----------------------|-----------|
| Canonical present     | 0         |
| Canonical missing     | −5 points |

## How to fix

Add `<link rel="canonical" href="https://example.com/this-page/">` to the `<head>`. The value should be the preferred, fully-qualified URL for the page.
