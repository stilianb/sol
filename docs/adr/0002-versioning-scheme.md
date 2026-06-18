# ADR-0002: Versioning scheme

**Status**: Accepted  
**Applies from**: M3 (v0.1.0)

## Decision

Versions track ship order, not milestone numbers. M3 is the first tagged release.

| Milestone | Version  |
|-----------|----------|
| M3        | `v0.1.0` |
| M4        | `v0.2.0` |
| M5        | `v0.3.0` |
| M6        | `v0.4.0` |
| M7        | `v0.5.0` |
| stable    | `v1.0.0` |

- Bug fixes within a milestone increment the patch digit (`v0.1.1`, `v0.1.2`).
- `build.zig.zon` is the single source of truth. The binary reads the version at build time and embeds it in the UA string.
- Every release is tagged `v<version>` on the exact release commit. Tags are never moved or deleted — bugs get a patch release.
- `build.zig.zon` is bumped in the same commit that gets tagged.
- No CHANGELOG pre-1.0. The milestone issues serve as the changelog.

## Context

`build.zig.zon` was initialised at `0.0.0`. M1–M2+ shipped without version bumps or tags. The UA string introduced in M3 requires a stable version number. Using milestone numbers as version minors would require back-tagging historical commits for M1/M2, which is busywork with no practical value.

## Alternatives considered

**Milestone-number versioning (M3 → 0.3.0)** — requires back-tagging M1/M2 to avoid a gap, and reordering milestones breaks the mapping. Rejected.

**Date-based versioning (YYYY.MM.DD)** — no release progression signal, harder to reason about compatibility. Rejected.

## Consequences

- Milestone labels (M3, M4, …) are planning names only — they do not map to version numbers.
- `0.x` semantics: breaking changes are permitted in any minor bump through M7. Stability guarantee begins at `v1.0.0`.
