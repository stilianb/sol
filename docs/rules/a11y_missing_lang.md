# a11y_missing_lang

**Category**: accessibility
**Severity**: critical
**Profiles**: all

## What we check

Checks whether the `<html>` element has a `lang` attribute with a non-empty value.

## Why it matters

Screen readers use the `lang` attribute to select the correct voice profile and pronunciation rules. Without it, content may be read in the wrong language. This is a WCAG 2.2 Level A failure (Success Criterion 3.1.1).

## How the score is affected

| Finding                   | Penalty    |
|---------------------------|------------|
| lang attribute present    | 0          |
| lang attribute missing    | −20 points |

## How to fix

Add `lang="en"` (or the appropriate BCP 47 language tag) to the `<html>` element. See [WCAG 3.1.1](https://www.w3.org/WAI/WCAG22/Understanding/language-of-page.html).
