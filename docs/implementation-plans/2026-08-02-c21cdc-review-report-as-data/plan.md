# c21cdc: Review report as data
<!-- plan-id: c21cdc -->
<!-- cip-stage: dr-round-1 -->
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

- [ ] 1.1 Add canonical draft-2020-12 `review-plan` and `review-run` schemas plus a single schema-owned limit/discriminator vocabulary. Prove native `Test-Json -SchemaFile` capability on the minimum PowerShell, positive minimum/maximum cases, one-above/layer-attribution failures, exact UTF-8/NFC/LF rules, and a maximum-envelope budget. Freeze a pre-change formatter golden corpus across cultures/platforms and add real graph coverage showing `8a0644` and `ca8ba8` blocked on `c21cdc`; update the suite coverage baseline for every renamed/added test ID in this step (REQ-1, REQ-3, REQ-4, REQ-5, REQ-9, REQ-11, REQ-12, RISK-2, RISK-3, RISK-7, RISK-9, RISK-10, RISK-12, RISK-14) `L`
- [ ] 1.2 Extract module-backed validation/canonicalization/render/publication functions and add `Freeze`/`Publish` modes to canonical `Build-ReviewReport.ps1` **beside** the still-working object API. Compute plan/generic run roots from repo inventory and UUID, resolve the schema relative to the installed script, freeze immutable tasks before dispatch, validate exact result slots, canonicalize bytes, encode/fence untrusted Markdown, perform byte-budget admission, publish immutable generations under a lock, and replace a digest-verifying manifest last. Implement exact exits/stdout/stderr and module-scoped publication fault injection; add the focused hostile/state/parity/admission/manifest/location/encoding tests while proving legacy fixtures remain green (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-10, REQ-11, REQ-12, RISK-1, RISK-2, RISK-3, RISK-5, RISK-6, RISK-7, RISK-9, RISK-11, RISK-12, RISK-13, RISK-14) [after: 1.1] `L`

## Phase 2: CR/DR adoption and consumer distribution
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Extend `Sync-PluginScripts.ps1` with a closed schema-sidecar declaration so it is the sole idempotent writer for the module/script/schema closure. Migrate CR and DR together: allocate a UUID, write and freeze the full task plan before dispatch, update result input per returned task, publish once, print the summary in chat, surface/preserve the manifest path, and treat exit `5` as degraded non-success after diagnostics. Update every skill/dispatch/collation/help surface, manifests, exact command-line approval regexes, installed caller tests, dogfood, marketplace, and registry; then remove `-Finding` and generated `[pscustomobject]` support only after both installed callers pass. Rely on one automatic patch bump per changed plugin (REQ-2, REQ-3, REQ-6, REQ-7, REQ-8, REQ-10, REQ-11, RISK-1, RISK-4, RISK-6, RISK-8, RISK-11, RISK-13) [after: 1.2] `L`
- [ ] 2.2 Add shared caller structural/eval cases that fail on wrong ordering, zero discovery, hand-built Markdown, alternate schema/root parameters, lost degraded artifacts, or unbounded file-tool retries. Execute clean, zero-finding, degraded, invalid, retry-after-injected-failure, plan-associated, and generic-runtime fixtures from one isolated CR install and one isolated DR install with no skalary-root fallback; assert no package/lockfile/vendored-validator changes and keep the focused run within its declared budget (REQ-7, REQ-8, REQ-10, REQ-12, RISK-4, RISK-8, RISK-11, RISK-12, RISK-14) [after: 2.1] `L`

## Phase 3: Reconciliation and proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Add indexed `review-reporting.design.md` as the durable owner and update copilot-customizations, plugin-registry runtime-state scope, enforcement-gap status, and both dependent-plan boundary notes. Map focused checks to ordinary-suite versus structural-eval ownership, prove every named test/eval is discovered, measure the representative 44-finding summary against the 66 KB baseline and the maximum-envelope time/memory target, run the ordinary suite/evals/generated drift gates, and use `Get-EpicRollup` to prove both dependent children remain blocked. If suite ceilings move, refresh evidence only through the existing measurement/import flow; finish with clean generated output (REQ-5, REQ-8, REQ-9, REQ-10, REQ-12, RISK-7, RISK-8, RISK-10, RISK-14) [after: 2.2] `L`

## Finalization (conditional)

<!-- Every @human step needs a <details> block carrying **Steps**, **Verify**, and **Rollback** —
     Test-Plan.ps1 fails the plan without it, and /ci prints the block verbatim at the handoff. -->

- [ ] 4.1 Review the frozen-plan truth, authoritative canonical JSON, hostile-input boundary, manifest publication, bounded summary/full artifacts, exact exits, and CR/DR consumer parity before approving the plan (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11, REQ-12, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11, RISK-12, RISK-13, RISK-14, RISK-15) @human [after: 3.1] `S`
  <details><summary>Details</summary>

  **Steps:**
     1. Inspect one clean, one zero-finding, and one degraded fixture's frozen plan, manifest, canonical JSON, summary, and full Markdown; verify every manifest digest and that no task/finding is silently absent.
  2. Run `@cr` over the schema, formatter, CR/DR callers and guides, tests, manifests, generated distribution files, design notes, and the `ca8ba8` dependency change, focusing on injection, path confinement, partial writes, bounds, and misleading model/attendance claims.
  3. Approve only when every blocking finding is resolved, all required evidence is recorded, the ordinary suite and structural evals pass, and `ca8ba8` remains blocked on this plan.

     **Verify:** `review:cr` is recorded; every `test:ReviewReport.*` and `test:Epic.ReviewRunConsumersDependOnContract` marker is discovered and passes; a degraded fixture publishes a valid manifest then returns `5`; native schema capability, hostile input, injected publication failures, bounds, maximum-envelope budget, consumer installs, plugin/dogfood/marketplace/registry drift, ordinary suite, and structural evals pass.

     **Rollback:** Before merge, return the affected step to `[~]`, remove approval, and repair the contract or fixture. After release, repair forward with higher patch versions; source reverts/downgrades do not recover installed consumers. Before `8a0644` or `ca8ba8` executes, add its dependency on the repair plan and keep it blocked until the corrected contract lands.

  </details>
