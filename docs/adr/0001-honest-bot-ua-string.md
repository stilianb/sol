# ADR-0001: Honest bot UA string

**Status**: Accepted  
**Milestone**: M3 (device profiles)

## Decision

`fetcher.zig` sends a declared bot UA string, never a browser impersonation:

```
sol/<version> (site auditor; https://github.com/stilianb/sol; profile=<name>)
```

The `profile=` suffix is the only device-profile signal in the UA. There is no Chrome/Safari/mobile UA spoofing.

## Context

The CLAUDE.md device profile table originally described a "UA hint" per profile, implying browser UA strings. M3 adds a `User-Agent` header for the first time.

## Alternatives considered

**Browser UA impersonation** — send the real Chrome/mobile UA for the active profile. Advantage: sites serve the same HTML a real browser would receive, making the audit data more representative. Rejected because: automated tooling at machine speed with a browser UA is indistinguishable from a scraper or credential-stuffing bot; sites have no way to opt out or verify intent.

## Consequences

- Sites that serve different HTML based on UA (bot-detection gates, lazy-load fences) may return different content than a real browser would. This is a known limitation — we accept it in exchange for honest disclosure.
- Sites can block sol by adding `User-agent: sol` / `Disallow: /` to `robots.txt`. `robots.zig` already respects this.
- The version string in the UA is read from build options at compile time. `build.zig.zon` is the single source of truth.
