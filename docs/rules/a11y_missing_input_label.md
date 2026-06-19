# a11y_missing_input_label

**Category**: accessibility
**Severity**: critical
**Profiles**: all

## What we check

Counts `<input>` elements that have no associated `<label>`, `aria-label`, or `aria-labelledby`.

## Why it matters

Screen reader users cannot identify what a form field is for without a programmatic label. This is a WCAG 2.2 Level A failure (Success Criterion 1.3.1, 4.1.2).

## How the score is affected

| Finding                    | Penalty    |
|----------------------------|------------|
| 0 inputs missing label     | 0          |
| 1–2 inputs missing label   | −10 points |
| 3+ inputs missing label    | −25 points |

## How to fix

Add a `<label for="input-id">` element for every visible input, or use `aria-label`/`aria-labelledby` for inputs that cannot have a visible label. See [WCAG 1.3.1](https://www.w3.org/WAI/WCAG22/Understanding/info-and-relationships.html).
