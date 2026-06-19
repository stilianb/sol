# bp_mixed_content

**Category**: best_practices
**Severity**: critical
**Profiles**: all

## What we check

On HTTPS pages, counts elements with `src` or `href` values that begin with `http://`.

## Why it matters

Mixed content allows attackers to intercept and tamper with resources loaded over unencrypted HTTP on an otherwise secure page, undermining the HTTPS guarantee.

## How the score is affected

| Finding                    | Penalty    |
|----------------------------|------------|
| 0 mixed-content resources  | 0          |
| 1–2 mixed-content resources| −10 points |
| 3+ mixed-content resources | −25 points |

## How to fix

Update all resource URLs to use `https://`. Add a `Content-Security-Policy: upgrade-insecure-requests` header as a fallback for legacy resources.
