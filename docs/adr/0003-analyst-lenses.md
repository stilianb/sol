# ADR-0003: Analyst Lenses Design

## Status
Planned — implementation pending

## Context
Three scoring dimensions (Brand, Experience, Conversion) cannot be automated from HTML analysis alone. They require human judgement, optionally AI-seeded from audit data + screenshots.

## Decision

### DB schema
`analyst_scores(project_id, lens, sub_scores JSONB, raw_observations, refined_observations, seeded_by_ai)`
`lens_artifacts(project_id, lens, file_path, label)`

### Sub-dimensions
| Lens | Sub-dimensions |
|---|---|
| brand | visual_language, voice_messaging, value_proposition, differentiation |
| experience | interface_design, content_taxonomy, navigation, responsiveness |
| conversion | cta_logic, form_design, trust_signals, funnel_design |

### Scoring
Each sub-dimension: score 0–5, observation text (string). Composite lens score = avg × 4 → 0–20. Overall retina score = sum of all 5 lenses (automated: perf, seo) + 3 analyst lenses = 0–100.

### AI seeding
`POST /projects/:id/lens/:lens/seed` calls Claude with:
- Lighthouse audit data
- BuiltWith tech stack
- Automated scores
- Optional: screenshot description (analyst-provided text)

Returns initial sub-scores + observations. Analyst edits from there. `seeded_by_ai = TRUE` flagged.

### Copilot
`POST /projects/:id/lens/:lens/copilot` — conversational Claude endpoint. Context: current sub-scores, observations, site audit data. Returns assistant message. Not persisted (session-only).

## Consequences
- Analyst must manually score 12 sub-dimensions per project (or accept AI seed)
- AI seeding requires ANTHROPIC_API_KEY set on server
- Artifacts (screenshots, annotated images) stored locally; S3 migration path via storage abstraction
