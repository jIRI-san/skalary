---
description: Active direct review, Git criteria, evidence, standards, history, compaction, and learning primitives.
globs:
  - scripts/skalary/{DirectWorkflow.psm1,Get-DirectPlanArtifactConsumerContext.ps1,Get-DesignNoteCompactionContext.ps1,Write-RecentLearning.ps1}
  - tests/skalary/DirectWorkflow*.Tests.ps1
---

# Direct workflow core

`DirectWorkflow.psm1` is shared by CR, DR, CI, and autopilot. The historical adapter serves CR, DR,
CEP, and CIP. Manifests install the canonical closure; `Sync-PluginScripts.ps1` owns generated copies.
The adapter imports only `PlanState.psm1`, `SecretGuard.psm1`, and `DirectWorkflow.psm1`, reads at most
three confined Markdown artifacts, screens secrets, and frames accepted content once. It has no retired
receipt, review-run, ledger, or harvest path.

Plan inventory includes only folders containing `plan.md`; retained transcript-only directories from an
archive move are artifacts, not duplicate plan identities.

| Primitive | Contract |
|---|---|
| `Test-PlanCriteriaBaseline` | Finds the unique Git commit introducing the current confirmation marker across active and archived plan paths, rejects staged marker drift, and compares both index and worktree intent, requirements, risks, and decisions by Git-filtered blob identity. |
| `Write-DirectReviewReport` | Atomically writes a confined stage report with fixed headings, complete-task enforcement, redaction, and a closed verdict. |
| `Invoke-DirectEvidence` | Evaluates supplied current tests/files and the active exact-scope review without persisted authority. |
| `Resolve-DirectReviewStandards` | Parses optional bounded local Markdown against caller-supplied base rules. |
| `ConvertTo-UntrustedReviewBlock` | Redacts high-confidence secrets and applies collision-safe framing. |
| `Get-DesignNoteCompactionContext.ps1` | Requires the canonical repository root, then uses Git paths and the active index to trigger finalization and batch candidates at five maximum. |
| `Write-RecentLearning.ps1` | Validates a completed source plan/commit and zero to ten cited, secret-free lessons, physically refuses linked write paths, then safely replaces the 16-KiB handoff. |

Reports at `assets/reviews/phase-<N>.md` or `final.md` are advisory. Native roles, budgets,
progress-based recovery, one-terminal-review sequencing, and visible non-clean stops remain readable
workflow instructions.

CI and autopilot share one installed compaction protocol: model judgment preserves semantics while the
helper owns deterministic trigger, active-index inventory, and batching. They also share the learning
writer; `/si` remains the reader-side trust boundary for format, source relationship, bounds,
citations, secrets, and untrusted framing.
