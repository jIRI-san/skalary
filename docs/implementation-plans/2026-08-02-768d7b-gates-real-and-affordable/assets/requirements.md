# Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | `Validate-Plan.ps1` distinguishes a scaffolded plan from a drafted one, and does not fail a plan that has not yet been drafted | A plan freshly created by `New-Plan.ps1` passes `validate.ps1` with exit 0; a drafted plan with a genuinely invalid marker still fails. `file:scripts/skalary/Validate-Plan.ps1#contains:Stage` · `test:ValidatePlan.ScaffoldedPlanPasses` | |

<!--
Seeded 2026-08-02 from the first real /cep run. Validate-Plan.ps1 line 37 invokes the validator at
-Stage Draft unconditionally, and New-Plan.ps1 writes no cip-stage anchor at scaffold time, so the
validator cannot tell "scaffolded, not yet drafted" from "drafted and broken". Scaffolding this
epic's seven children turned the repo red before a word was authored.

The immediate symptom -- the marker legend in REQ-1's criteria cell carried the literal `count>=<N>`,
which Test-Plan rejects as an invalid assertion -- was fixed at the source in
scripts/skalary/New-Plan.ps1 and synced through the payload pipeline. That makes the placeholder
valid; it does not give the validator a notion of stage, which is the real gap and belongs here.

Remaining requirements for this child are captured when /cip drafts it: CI running the whole suite
(Cluster B), host/container -Force parity, locale-deterministic catalog ordering (Cluster E), gated
constants (Cluster C), and the 29-minute suite cost (Cluster H).
-->

