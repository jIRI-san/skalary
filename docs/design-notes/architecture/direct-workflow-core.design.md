---
description: Active direct review, Git criteria, evidence, standards, and historical-context primitives.
globs:
  - scripts/skalary/DirectWorkflow.psm1
  - scripts/skalary/Get-DirectPlanArtifactConsumerContext.ps1
  - tests/skalary/DirectWorkflow*.Tests.ps1
---

# Direct workflow core

`DirectWorkflow.psm1` is the active shared module for CR, DR, CI, and autopilot. The direct historical
adapter is active for CR, DR, CEP, and CIP. Plugin manifests install the canonical script closure;
`Sync-PluginScripts.ps1` owns generated copies and dogfood follows manifest activation.

| Function | Contract |
|---|---|
| `Test-PlanCriteriaBaseline` | Finds the unique Git commit introducing the current confirmation marker and byte-compares intent, requirements, risks, and decisions. |
| `Write-DirectReviewReport` | Atomically writes the confined stage report with fixed headings, complete-task enforcement, secret redaction, and a closed verdict. |
| `Invoke-DirectEvidence` | Evaluates supplied current test results, confined current files, and the active exact-scope review result without persistence. |
| `Resolve-DirectReviewStandards` | Parses optional bounded local Markdown standards against caller-supplied base rules. |
| `ConvertTo-UntrustedReviewBlock` | Redacts high-confidence secrets and frames repository text with a collision-safe delimiter. |

Plan reports are `assets/reviews/phase-<N>.md` or `assets/reviews/final.md`; persisted reports are
advisory. The historical adapter reads at most five selected current Markdown artifacts through
`PlanState` confinement, screens secrets, and frames accepted content once. It has no receipt
dependency.

Native roles, budgets, progress-based recovery, one-terminal-review sequencing, and visible non-clean
stops remain readable instructions rather than scheduler state.
