# seo_missing_description

**Category**: seo
**Severity**: warning
**Profiles**: all

## What we check

Checks whether the page has a `<meta name="description">` element with non-empty content.

## Why it matters

Search engines often use the meta description as the snippet shown below the title in results. A missing description means the engine will choose arbitrary page text, which is rarely optimal for click-through rates.

## How the score is affected

| Finding                   | Penalty    |
|---------------------------|------------|
| Description present       | 0          |
| Description missing       | −10 points |

## How to fix

Add `<meta name="description" content="...">` to the `<head>`. Aim for 120–160 characters. Write it as a human-readable summary that encourages users to click.
