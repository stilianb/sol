# a11y_positive_tabindex

**Category**: accessibility
**Severity**: warning
**Profiles**: all

## What we check

Counts elements with a `tabindex` value greater than 0.

## Why it matters

Positive tabindex values override the natural document tab order, creating a confusing and unpredictable navigation experience for keyboard and assistive technology users. WCAG 2.2 Success Criterion 2.4.3.

## How the score is affected

| Finding                        | Penalty   |
|--------------------------------|-----------|
| 0 positive tabindex elements   | 0         |
| 1–2 positive tabindex elements | −5 points |
| 3+ positive tabindex elements  | −15 points|

## How to fix

Remove positive `tabindex` values. Use `tabindex="0"` to add elements to the natural tab order, or restructure the DOM so the visual and focus order match. See [WCAG 2.4.3](https://www.w3.org/WAI/WCAG22/Understanding/focus-order.html).
