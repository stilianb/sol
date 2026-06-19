# perf_render_blocking_scripts

**Category**: performance
**Severity**: warning (1–2 scripts), critical (3+)
**Profiles**: all

## What we check

Counts `<script>` elements with a `src` attribute and no `async` or `defer` attribute in the HTML `<head>`.

## Why it matters

Render-blocking scripts pause the browser from displaying the page until the script is downloaded and executed. On mobile networks this can delay first paint by seconds.

## How the score is affected

| Finding                    | Penalty     |
|----------------------------|-------------|
| 0 render-blocking scripts  | 0           |
| 1–2 render-blocking scripts| −10 points  |
| 3+ render-blocking scripts | −25 points  |

## How to fix

Add `defer` to scripts that don't need to run before page render, or `async` to independent analytics/tracking scripts. Move non-critical scripts before `</body>`.

## Profile notes

Penalty is the same across profiles; the wall-clock impact is proportionally worse on mobile due to 1.6 Mbps throttle.
