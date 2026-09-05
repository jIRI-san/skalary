---
description: Active direct review, Git criteria, evidence, standards, and historical-context primitives.
globs:
  - scripts/skalary/{DirectWorkflow.psm1,Get-DirectPlanArtifactConsumerContext.ps1,Get-DesignNoteCompactionContext.ps1}
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
| `Get-DesignNoteCompactionContext.ps1` | Uses Git changed paths and the active design-note index to decide the finalization trigger and split selected candidates into batches of at most five. |
| `Write-RecentLearning.ps1` | Validates a completed source plan/commit and zero to ten cited, secret-free lessons, then safely replaces the strict 16-KiB Markdown handoff. |

Plan reports are `assets/reviews/phase-<N>.md` or `assets/reviews/final.md`; persisted reports are
advisory. The historical adapter reads at most five selected current Markdown artifacts through
`PlanState` confinement, screens secrets, and frames accepted content once. It has no receipt
dependency.

Native roles, budgets, progress-based recovery, one-terminal-review sequencing, and visible non-clean
stops remain readable instructions rather than scheduler state.

The CI and autopilot consumers share the installed design-note compaction protocol. It is a single
conditional finalization action, not a service or durable state machine; model judgment owns semantic
preservation, while the helper owns deterministic trigger, active-index inventory, and batching.

The same consumers bundle the recent-learning writer. `/si` is the trust boundary: its reader checks
format, source relationship, bounds, citations, and secrets before collision-safe untrusted framing.
