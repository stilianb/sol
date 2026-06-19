# perf_missing_image_dims

**Category**: performance
**Severity**: warning
**Profiles**: all

## What we check

Counts `<img>` elements that have no `width` and `height` attributes in the HTML.

## Why it matters

Without explicit dimensions the browser can't reserve space for images while they load, causing layout shift (CLS). Layout shift hurts perceived performance and Lighthouse CLS score.

## How the score is affected

| Finding                    | Penalty    |
|----------------------------|------------|
| 0 images missing dims      | 0          |
| 1–3 images missing dims    | −5 points  |
| 4+ images missing dims     | −15 points |

## How to fix

Add `width` and `height` attributes matching the intrinsic image dimensions. Use `height: auto` in CSS to preserve aspect ratio on responsive layouts.
