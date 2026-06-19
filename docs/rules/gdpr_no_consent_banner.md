# gdpr_no_consent_banner

**Category**: gdpr
**Severity**: critical
**Profiles**: all

## What we check

Fires when known third-party trackers are detected in the page HTML but no consent banner or consent management platform (CMP) is detected.

## Why it matters

Under GDPR and ePrivacy, collecting personal data via tracking cookies requires explicit prior consent from EU users. Loading trackers without a consent banner is a legal violation that can result in significant fines.

## How the score is affected

| Finding                                             | Penalty    |
|-----------------------------------------------------|------------|
| No trackers, or trackers with consent banner        | 0          |
| Trackers present and no consent banner detected     | −30 points |

## How to fix

Integrate a consent management platform (OneTrust, Cookiebot, CookieYes, etc.) and configure it to block tracker scripts until the user consents. Ensure the banner fires on first visit before any tracking code runs.
