# a11y_viewport_zoom_disabled

**Category**: accessibility
**Severity**: critical
**Profiles**: all

## What we check

Detects `<meta name="viewport">` content that includes `user-scalable=no` or `maximum-scale=1`.

## Why it matters

Low-vision users rely on browser zoom to read content. Disabling zoom is a WCAG 2.2 Level AA failure (Success Criterion 1.4.4 Resize Text).

## How the score is affected

| Finding                        | Penalty    |
|--------------------------------|------------|
| Zoom not disabled              | 0          |
| Zoom disabled via viewport meta| −15 points |

## How to fix

Remove `user-scalable=no` and `maximum-scale` (or set `maximum-scale=5`) from the viewport meta tag. Modern responsive layouts work correctly without disabling zoom. See [WCAG 1.4.4](https://www.w3.org/WAI/WCAG22/Understanding/resize-text.html).
