# Domain Model

## Terms and meanings

- **AI credit** — GitHub's token-priced billing unit; one credit is currently USD 0.01.
- **Operating budget** — 180,000 credits available for planned work in a month.
- **Reserve** — 20,000 credits held outside ordinary work for incidents and unexpected completion cost.
- **Default context** — the normal Copilot context tier. Long context is removed rather than retained as
  an operator option.
- **Delegated call** — one model-backed child-agent invocation or retry. Built-in file, search, and
  command tools are not delegated calls.
- **Escalation** — a model upgrade justified by an observable task property or unresolved evidence, not
  by role attendance.

## Actors and boundaries

- The operator owns the GitHub budget, monthly dashboard review, and any exceptional expensive run.
- Skills and agents own concise routing guidance, call caps, context selection, and deterministic stop
  conditions.
- GitHub owns model availability and token prices; repository guidance records a dated snapshot and
  links to the authoritative pricing table instead of encoding billing logic.
- Tier-2 waza evals are an explicit premium boundary. Tier-1 Pester and normal validation remain offline
  and zero-credit.

## Invariants

- Active workflows use default context only.
- Routine work starts with direct tools or the least expensive suitable model and escalates at most one
  tier at a time from concrete evidence.
- A fallback replaces an unavailable model; it never adds a parallel panel.
- Expensive independent review requires a concrete security, correctness, concurrency, destructive,
  or architectural risk.
- Budget guidance stays human-readable and advisory; no repository service tracks or enforces credits.
