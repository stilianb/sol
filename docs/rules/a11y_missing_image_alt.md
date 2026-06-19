# a11y_missing_image_alt

**Category**: accessibility
**Severity**: critical
**Profiles**: all

## What we check

Counts `<img>` elements that have no `alt` attribute and are not marked as decorative (`role="presentation"` or `alt=""`).

## Why it matters

Screen reader users have no way to understand what an image conveys without alternative text. This is a WCAG 2.2 Level A failure (Success Criterion 1.1.1).

## How the score is affected

| Finding                  | Penalty    |
|--------------------------|------------|
| 0 images missing alt     | 0          |
| 1–2 images missing alt   | −10 points |
| 3+ images missing alt    | −25 points |

## How to fix

Add a descriptive `alt` attribute to every meaningful image. For decorative images use `alt=""`. See [WCAG 1.1.1](https://www.w3.org/WAI/WCAG22/Understanding/non-text-content.html).
