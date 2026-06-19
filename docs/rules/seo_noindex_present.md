# seo_noindex_present

**Category**: seo
**Severity**: critical
**Profiles**: all

## What we check

Checks whether `<meta name="robots">` contains the `noindex` directive.

## Why it matters

`noindex` tells search engines not to include the page in their index. If set unintentionally on a page that should rank, it will receive no organic traffic.

## How the score is affected

| Finding            | Penalty    |
|--------------------|------------|
| noindex absent     | 0          |
| noindex present    | −30 points |

## How to fix

Remove the `noindex` directive if the page should appear in search results. Verify staging environments don't accidentally ship `noindex` to production via environment-specific meta tags.
