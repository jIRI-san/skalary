# Decision: size reduction is a best-effort goal, not a gated requirement

## Context

The headline motivation for this plan is reducing token consumption of the `/ci` and `/cip` skills — smaller base `SKILL.md` files, less duplicated schema prose across assets, and less per-loop re-derivation of plan state.

The `evidence` gate requires every REQ to carry a machine-checkable typed marker. The closed `file:` assertion vocabulary is `exists` · `contains:<regex>` · `count>=<N>` · `dircount>=<N>` — there is **no size-upper-bound assertion** (`size<=N` / `linecount<=N`).

## Options considered

1. **Pester size-budget test** asserting each skill/asset byte+line count is ≤ a target. Works without grammar change, but bakes brittle absolute numeric budgets into a test that would churn on every legitimate edit.
2. **Extend the marker grammar** with `size<=N`/`linecount<=N`. More reusable, but expands the durable evidence contract (`PlanEvidence.psm1` + `Test-Plan.ps1` + design note) for a one-off goal.
3. **Best-effort reduction, no hard size gate.** Reduction is pursued and reviewed, but not encoded as blocking evidence.

## Decision

Option 3. Size reduction is a **goal**, validated by review (`@cr`/`@dr`) and the visible diff, not by a blocking marker.

Each REQ instead carries **functional** evidence that indirectly enforces the intent:

- Duplicated capture-schema prose is **moved** into `Add-WorkflowNote.ps1`; skills are proven to reference the script (`file:#contains:Add-WorkflowNote`) rather than re-embed the schema.
- Deterministic steps are proven to be **scripted** (`Get-PlanState`, `Resolve-Plan`, `New-Plan`) and wired into the orchestrators.
- Functionality preservation is gated by the existing `ci`/`cip` structural evals plus new behavior tests.

## Consequences

- No brittle absolute-size assertions to maintain.
- "Smaller" is enforced by the centralization REQs + human review, not by a number.
- If a hard size budget is wanted later, option 2 (grammar extension) is the clean path and can be its own plan.
