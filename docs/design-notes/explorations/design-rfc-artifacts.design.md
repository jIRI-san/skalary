---
description: Deferred exploration — agent-authored RFC-style design packages (short markdown plus mermaid) describing how a plan will be implemented, reviewed as part of human plan approval. Load before changing the /cip approval flow or plan asset set.
globs:
  - plugins/create-implementation-plan/**
  - docs/implementation-plans/**
---

# Design RFC Artifacts

Operator note captured 2026-07-31 during `b0c0d3` execution. **Not yet analysed** — recorded for the align phase.

## Proposal

For more complicated implementations, agents should produce a short RFC-style design package — markdown with mermaid diagrams — describing *how* the design is going to be implemented, derived from the plan. The package becomes part of what the human operator approves, alongside the plan itself.

Explicitly bounded by the operator: **"nothing too long."** The value is in the diagram and the shape of the approach, not a specification document.

## Why this is not redundant with the plan

A plan is a checklist of steps with requirements and evidence. It deliberately does not show structure: what talks to what, where the boundaries fall, what the data flow looks like. Two very different architectures can produce nearly identical step lists, and the difference only becomes visible once the code exists — which is the expensive moment to discover it.

A diagram surfaces that difference at approval time, when changing it is cheap. This is the same argument that justifies design review of the plan, applied one level down to the implementation shape.

## Open questions

| Question | Note |
|---|---|
| When does it trigger? | "More complicated implementations" needs a rule — phase-budget points, step count, subsystem count, or explicit operator request |
| Where does it live? | `assets/` under the plan folder is the obvious home given the `b0c0d3` layout; possibly `assets/design/` if multi-file |
| Who reviews it? | `dr` already reviews plans; whether the RFC is a separate DR pass or folded into the existing one is undecided |
| Enforcement | If approval is a gate, it needs a machine-checkable marker; if advisory, say so rather than implying a gate |
| Staleness | A diagram that drifts from the implementation is worse than none — needs either a freshness rule or an explicit "as-designed, not as-built" label |

## Interaction with shipped work

Fits the `b0c0d3` `assets/` layout (REQ-1) directly — an RFC package is another asset with a one-line link from `plan.md`. No conflict with the shipped design; sequencing after it avoids rework on the asset resolver.
