# bp_missing_https

**Category**: best_practices
**Severity**: critical
**Profiles**: all

## What we check

Checks whether the audited page URL begins with `https://`.

## Why it matters

HTTP pages transmit data in plain text, allowing anyone on the network to read or modify content. Browsers mark HTTP pages as "Not Secure", which reduces user trust and conversion rates.

## How the score is affected

| Finding            | Penalty    |
|--------------------|------------|
| Page is HTTPS      | 0          |
| Page is HTTP       | −30 points |

## How to fix

Obtain a TLS certificate (free via Let's Encrypt) and configure the server to redirect all HTTP traffic to HTTPS. Set `Strict-Transport-Security` headers once HTTPS is stable.
