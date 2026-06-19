# perf_inline_script_bytes

**Category**: performance
**Severity**: info (5–20 KB), warning (20+ KB)
**Profiles**: all

## What we check

Sums the byte length of all inline `<script>` blocks (scripts without a `src` attribute).

## Why it matters

Large inline scripts increase HTML document size and block parsing. Unlike external scripts, inline scripts cannot be cached by the browser.

## How the score is affected

| Finding                  | Penalty    |
|--------------------------|------------|
| ≤5 KB inline script      | 0          |
| 5–20 KB inline script    | −5 points  |
| 20+ KB inline script     | −15 points |

## How to fix

Move large inline scripts to external `.js` files so they benefit from browser caching. Inline only what is strictly required for above-the-fold rendering.
