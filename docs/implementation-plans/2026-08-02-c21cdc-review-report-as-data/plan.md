# c21cdc: Review report as data
<!-- plan-id: c21cdc -->
<!-- cip-stage: dr-round-3 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Design-review evolution — [assets/evolution-log.md](assets/evolution-log.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Validated review artifact MVP
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add canonical `review-plan`, `review-run`, `review-manifest`, and terminal-status schemas plus one schema-owned limit vocabulary. Keep wrapper compatibility at `#requires 7.0` but explicitly gate/prove PowerShell 7.6+ schema capability on every supported CI leg, including bounded exit-2 status when absent. Commit the real 44-finding corpus/pre-change bytes, old semantic projection, and separate new-layout goldens across culture/platform; add edge/state fixtures and only additive test inventory entries (REQ-1, REQ-3, REQ-4, REQ-5, REQ-9, REQ-11, REQ-12, RISK-2, RISK-3, RISK-7, RISK-9, RISK-10, RISK-12, RISK-14) `L`
- [x] 1.2 Extract module-backed validation/canonicalization/render/publication/reader functions and add `Freeze`/`Publish` beside the working object API. Add `ReviewRuns` resolution; fixed temp/input handshakes; immutable digest/state/replay rules; exact slots; canonical/encoded untrusted fields; versioned secret allow/block corpus with immediate rejected-input destruction; byte admission; 5-second lock; confined manifest-last publication; verifying summary reader; generic cleanup helper; bounded statuses; and fault seams. Secret fixtures must store only inert fragments and reconstruct token-shaped values at test runtime; never commit a complete provider-token signature that triggers repository push protection. Focused tests cover hostile/mutation/replay/lock/secret/semantic-parity/admission/manifest/read/location/encoding/max-envelope behavior while legacy tests remain green (REQ-1, REQ-3, REQ-4, REQ-5, REQ-6, REQ-10, REQ-11, REQ-12, RISK-1, RISK-2, RISK-3, RISK-5, RISK-6, RISK-7, RISK-9, RISK-11, RISK-12, RISK-14, RISK-16) [after: 1.1] `L`

## Phase 2: CR/DR adoption and consumer distribution
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Extend `Sync-PluginScripts.ps1` closure scanning to literal `$PSScriptRoot` `.schema.json` references resolved only from canonical `schemas/review/`; copy/prune schema plus module/script/reader/cleanup closure into both plugins while legacy callers still work, with no new manifest field. Map files explicitly, synchronize dogfood/marketplace/registry, and prove idempotent `-WhatIf`, stale cleanup, per-step automatic patch bumps, and root/plugin/dogfood parity (REQ-8, RISK-8, RISK-13) [after: 1.2] `M`
- [x] 2.2 Migrate CR and DR together: add `edit` with the two-input-only absolute rule; Freeze once before every independent dispatch with no prior-result priming/suppression; collect results in memory; write/Publish once; verify/read summary; preserve plan manifest; cleanup generic run; and finalize any earlier frozen orphan as cancelled. Implement complete `0/5/2/3/4` behavior and terminal exit-3 narrower-scope restart. Update every agent/skill/dispatch/collation/help surface, plugin mappings, secret rules, and `Set-ScriptApproval` object-valued exact add/remove exception; synchronize outputs, then retire `-Finding`/generated objects only after both installed callers pass, recording every baseline removal reason here (REQ-2, REQ-3, REQ-6, REQ-7, REQ-8, REQ-10, REQ-11, REQ-13, RISK-1, RISK-4, RISK-6, RISK-8, RISK-11, RISK-13, RISK-16, RISK-17) [after: 2.1] `L`

## Phase 3: Consumer truth and reconciliation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Add stable, separately asserted CR/DR structural IDs that fail on unsafe writer scope, wrong ordering, prior-result priming, missing dispatch, zero discovery, hand-built Markdown, alternate policy/root, lost degraded artifacts, or unbounded retries. Execute clean/zero/degraded/all-failure exits, orphan abandonment, frozen mutation, fault/lock retry, plan/generic cleanup, secret guard, and reader fixtures from isolated CR and DR installs with no root fallback; assert no package/lockfile/vendor changes. Preserve one final live `review:cr` published artifact as observed runtime evidence, without treating structural evals as runtime proof (REQ-2, REQ-7, REQ-8, REQ-10, REQ-11, REQ-12, RISK-4, RISK-8, RISK-11, RISK-12, RISK-14, RISK-16, RISK-17) [after: 2.2] `M`
- [x] 3.2 Add indexed `review-reporting.design.md` and update plan-workflow plus plan templates for `ReviewRuns`, copilot-customizations, plugin-manager approval exception, plugin-registry runtime state, consumer PowerShell prerequisite/provisioning, autopilot-skill's stale `Test-Json` claim, enforcement-gap note and both index rows, and dependent boundaries. Map ordinary/eval/live-review evidence, prove exact IDs, measure the committed 44-finding corpus and required cross-platform maximum envelope, run suites/evals/drift, and prove real edges plus synthetic blocked-state equivalence. Refresh suite evidence only through existing flow; finish clean (REQ-5, REQ-8, REQ-9, REQ-10, REQ-12, RISK-7, RISK-8, RISK-10, RISK-12, RISK-14) [after: 3.1] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review frozen-plan truth, canonical JSON, safe writer/secret boundary, verifying manifest reader, bounded views, exact exits, and CR/DR parity before approval (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, REQ-13, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11, RISK-12, RISK-13, RISK-14, RISK-15, RISK-16, RISK-17) @human [after: 3.2] `S`
  <details><summary>Details</summary>

  **Steps:**
     1. Inspect one clean, one zero-finding, and one degraded fixture's frozen plan, manifest, canonical JSON, summary, and full Markdown; verify every manifest digest and that no task/finding is silently absent.
   2. Run `@cr` over schemas, formatter/module, CR/DR callers and guides, tests/evals, manifests, generated distribution files, design notes, approvals, and both dependency changes, focusing on injection/secret echo, path confinement, publication/retry, bounds, and misleading model/attendance claims.
  3. Approve only when every blocking finding is resolved, all required evidence is recorded, the ordinary suite and structural evals pass, and `ca8ba8` remains blocked on this plan.

   **Verify:** the final `review:cr` artifact is published and recorded; every `test:ReviewReport.*` and `test:Epic.ReviewRunConsumerEdgesAndState` marker is discovered and passes; a degraded fixture publishes then returns `5`; schema capability, hostile/secret input, publication faults, bounds, cross-platform maximum envelope, consumer installs, drift, ordinary suite, and structural evals pass.

     **Rollback:** Before merge, return the affected step to `[~]`, remove approval, and repair the contract or fixture. After release, repair forward with higher patch versions; source reverts/downgrades do not recover installed consumers. Before `8a0644` or `ca8ba8` executes, add its dependency on the repair plan and keep it blocked until the corrected contract lands.

  </details>
