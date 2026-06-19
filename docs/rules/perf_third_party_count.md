# perf_third_party_count

**Category**: performance
**Severity**: info (3–5 domains), warning (6+ domains)
**Profiles**: all

## What we check

Counts distinct third-party script and stylesheet domains loaded from the page HTML.

## Why it matters

Each third-party domain requires a DNS lookup, TCP handshake, and TLS negotiation. On mobile with high RTT these add up and delay page render.

## How the score is affected

| Finding                | Penalty    |
|------------------------|------------|
| 0–2 third-party domains| 0          |
| 3–5 third-party domains| −5 points  |
| 6+ third-party domains | −15 points |

## How to fix

Audit which third-party scripts are actually needed. Self-host fonts and analytics if possible. Add `<link rel="preconnect">` for unavoidable third-party origins.
