---
name: cip
description: 'Create Implementation Plan — confirm criteria and draft an implementation-ready vertical plan.'
argument-hint: 'Plan name or existing plan reference'
user-invocable: true
disable-model-invocation: true
context: fork
---

# Create Implementation Plan

Resolve/scaffold the plan with existing deterministic scripts. Discover prior work only from a filtered
index or explicit canonical IDs, then load at most five selected current Markdown artifacts through
`.github/skills/cip/scripts/Get-DirectPlanArtifactConsumerContext.ps1`. Keep confinement, secret
screening, accepted-only provenance, untrusted framing, and current intent/contracts above history.

Before drafting, follow
[`./assets/decision-protocol.md`](./assets/decision-protocol.md). It defines host-equivalent complex
choices and the absolute/fuzzy language confirmation gate. Do not draft an unconfirmed absolute or an
unobservable fuzzy requirement.

Confirm current intent first. If a choice spans design and acceptance criteria, use one native combined
design/requirements call; otherwise the orchestrator drafts it directly. A Judge is the normal second
call. Use two delegated calls by default, five maximum including replacement, at most five supporting
artifacts, and 600/1,200 prompt
bounds. Use a direct risk-selected DR only for concrete unresolved design risk; no scheduler or fixed
matrix. For observable background calls, two no-progress checks permit one same-agent redirect and at
most one replacement. Elapsed agent time never cancels work; declared deterministic command timeouts
remain.

Before final drafting, confirm the current intent, requirements, risks, and decisions together. Persist
the existing planning-confirmed marker only after that confirmation. Typed evidence remains exactly
`test:`, `file:`, and `review:`. Draft MVP-first vertical steps and retain script-owned validation/stage
mutations. Any later criteria correction returns to the affected confirmation rather than weakening it.
