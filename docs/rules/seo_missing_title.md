# seo_missing_title

**Category**: seo
**Severity**: critical
**Profiles**: all

## What we check

Checks whether the page has a `<title>` element with non-empty text.

## Why it matters

The page title is the primary signal search engines use to understand page content. It is also displayed as the clickable headline in search results. A missing title means the page will likely not rank for any meaningful query.

## How the score is affected

| Finding            | Penalty    |
|--------------------|------------|
| Title present      | 0          |
| Title missing      | −20 points |

## How to fix

Add a concise, descriptive `<title>` element in the `<head>`. Aim for 50–60 characters. Each page should have a unique title.
