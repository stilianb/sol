# seo_missing_sitemap

**Category**: seo
**Severity**: info
**Profiles**: all

## What we check

Checks whether an XML sitemap was found via `robots.txt` `Sitemap:` directive or at the default `/sitemap.xml` location.

## Why it matters

A sitemap helps search engines discover and prioritise pages, especially for large or deep sites. Without one, some pages may not be crawled.

## How the score is affected

| Finding             | Penalty   |
|---------------------|-----------|
| Sitemap found       | 0         |
| Sitemap not found   | −5 points |

## How to fix

Generate an XML sitemap and serve it at `/sitemap.xml`. Add a `Sitemap:` directive to `robots.txt`. Submit the sitemap URL in Google Search Console.
