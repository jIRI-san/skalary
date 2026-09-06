# 623cc2: Simple plugin lifecycle
<!-- plan-id: 623cc2 -->
<!-- depends-on: 2aa7ec, 33a78a -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:129a377063067ce15f41afbc18200a28e391d3ae46409e096983ab50525d42ed -->
<!-- epic: 705e6c -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

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
- Domain model — [assets/domain.md](assets/domain.md)
- Approved design — [assets/design.md](assets/design.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Review results — advisory `assets/reviews/phase-<N>.md` and `assets/reviews/final.md`
- AI-credit ledger — `assets/ai-credits.json` (created by autonomous execution)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Minimal direct lifecycle
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Replace file-ownership receipts with the minimal installed-version receipt and direct shape validation (REQ-2, REQ-7, RISK-2, RISK-6) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** each installed plugin has one confined receipt containing only `name`, `version`, `sourceIdentity`, and immutable `ref`; list/get/dependency checks use it for installed and outdated status without file ownership, degraded state, timestamps, or a schema.

  **Likely touchpoints:** `scripts/skalary/_Common.ps1`, `Get-Plugin.ps1`, `Find-Plugin.ps1`, `Remove-Plugin.ps1`, receipt schema/assets, plugin-manager bundled copies, and focused receipt tests.

  **Constraints:** validate the closed receipt shape directly; canonicalize and re-check the receipt path before reads and writes; do not add a lockfile, migration, dual reader, or replacement schema.

  **Verify:** focused tests prove valid installed/outdated detection and visible refusal of malformed, mismatched, escaping, linked, or legacy-shaped receipts.

  **Stop/escalate when:** an active external consumer is proven to require a removed receipt field; stop for an explicit compatibility decision rather than retaining it speculatively.

  </details>
- [x] 1.2 Simplify install and update to confined direct writes, result verification, and receipt-last convergence (REQ-1, REQ-3, REQ-4, RISK-1, RISK-3, RISK-4) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** install refuses unowned collisions unless forced; update uses a matching minimal receipt to detect version/ref changes, replaces the plugin's old and new manifest-owned paths, verifies the resulting bytes in memory, and writes the new receipt only after success; unchanged reruns make no change.

  **Likely touchpoints:** `scripts/skalary/{Install-Plugin,Update-Plugin,_Common}.ps1`, plugin-manager install/update script bundles, and focused consumer lifecycle tests.

  **Constraints:** physically canonicalize every payload, receipt, temporary, and parent path before access; refuse rooted/traversing/link/reparse paths and `.github/workflows/**`; retain dependency ordering and immutable source resolution; no mutation lock, transaction, backup, journal, rollback claim, or automatic retirement side effect.

  **Verify:** focused install/update tests cover clean install, unchanged rerun, version update, source mismatch, unowned collision, forced collision, old-path removal, interruption-visible retry, and all confinement refusals.

  **Stop/escalate when:** the prior immutable ref cannot be materialized to derive the installed manifest, or a manifest maps two plugins to the same destination; fail without advancing the receipt and stop for operator action.

  </details>
- [x] 1.3 Replace transactional removal and automatic retirement with preflighted explicit removal and retired-name refusal (REQ-1, REQ-5, REQ-6, RISK-1, RISK-2, RISK-3, RISK-5) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** remove derives the exact installed manifest from the receipt ref, preflights the complete delete set, refuses before any deletion when a present file differs unless `-Force`, deletes missing-safe targets and the receipt last, and converges on retry; install/update refuse published retired names and direct the operator to explicit removal.

  **Likely touchpoints:** `scripts/skalary/{Remove-Plugin,Install-Plugin,Update-Plugin,_Common}.ps1`, `registry-retirements.json`, plugin-manager skills/bundles, and focused removal/retirement tests.

  **Constraints:** keep dependent-plugin refusal unless forced; retain published retired-name and pinned-manifest metadata; remove `-ApplyRetirements`, preview/apply, cursor, replay, recovery, terminal-record, and background reconciliation behavior.

  **Verify:** focused tests prove all-or-nothing modified-file refusal, explicit force removal, missing-file convergence, dependent refusal, retired-target refusal, pinned retired-manifest removal, and no unrelated retirement mutation.

  **Stop/escalate when:** the receipt source/ref or retired pinned manifest cannot be resolved safely; report the exact missing authority and do not guess paths or delete the receipt.

  </details>

## Phase 2: Machinery retirement and focused evidence
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Delete lifecycle locks, journals, backups, file-hash/degraded receipt logic, retirement runtime state, schemas, fixtures, and callers as one closed cut (REQ-2, REQ-6, REQ-7, RISK-3, RISK-6) [after: 1.3] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** active source and installed plugin-manager payload contain no mutation lock, transaction journal, backup/recovery, CAS, degraded/file-outcome receipt, retirement preview/cursor/result, automatic apply, or lifecycle schema path.

  **Likely touchpoints:** `scripts/skalary/_Common.ps1`, lifecycle entry points, `schemas/{receipt,retirement}/**`, plugin manifests and generated script closures, `.github/.skalary` dogfood residue, transferred tests, and active guidance.

  **Constraints:** retain only minimal receipts and the catalog source/published retirement metadata selected by the operator; delete obsolete code instead of leaving compatibility helpers; preserve unrelated plugin registry and source-identity utilities.

  **Verify:** a closed residue test enumerates removed commands, switches, functions, state paths, schemas, manifest entries, bundled copies, and active documentation references.

  **Stop/escalate when:** a removed symbol is still required by a retained non-lifecycle consumer; separate the local shared helper from retired behavior rather than deleting or preserving the whole subsystem.

  </details>
- [x] 2.2 Rewrite lifecycle tests around current user behavior, external formats, and high-impact confinement regressions (REQ-1, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-9, RISK-1, RISK-3, RISK-4, RISK-5, RISK-7) [after: 2.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** focused tests cover the complete direct lifecycle and retirement refusal while obsolete transaction/recovery/state matrices and low-value fixture history are deleted.

  **Likely touchpoints:** `tests/skalary/{PluginRetirement,ConsumerInstall,Marketplace,PluginScriptBundle,Skalary}.Tests.ps1`, `tests/ConsumerInstallFixture.psm1`, and retirement fixtures.

  **Constraints:** map each retained case to current user behavior, an external format, or a high-impact regression; reuse the production installer and manifest-derived foreign fixture; do not add a test protocol, broad matrix, or routine full-repository run.

  **Verify:** selected lifecycle and consumer tests pass through `Run-UnitTests.ps1 -TestPath` within the focused 30/60-second contract.

  </details>
- [x] 2.3 Keep plugin manifests, registry, marketplace, retirement catalog source, and direct command contracts coherent (REQ-6, REQ-8, REQ-9, RISK-5, RISK-6, RISK-7) [after: 2.2] `S`

## Phase 3: Distribution, contracts, and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Update the installer architecture contract, plugin lifecycle design notes, plugin-manager guidance, and operator-facing skills for the confirmed direct behavior and accepted safety tradeoffs (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-9, RISK-2, RISK-4, RISK-6) [after: 2.3] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** active architecture/design notes and plugin-manager skills describe minimal version receipts, explicit overwrite/remove authority, receipt-last visible failure, retired-name refusal, and the absence of transactional recovery.

  **Likely touchpoints:** `docs/architecture-notes/arch-install-confinement.md`, `docs/design-notes/architecture/{plugin-registry,plugin-manager}.design.md`, their indexes, and `plugins/plugin-manager/skills/**`.

  **Constraints:** preserve the locked/provisional contract maintenance rules; record the simple-over-safe interruption and local-edit tradeoffs under `## Dubious decisions`; remove stale claims rather than documenting compatibility.

  **Verify:** active-document and installed-skill residue checks find no removed lifecycle behavior and all direct command examples match the shipped parameters.

  </details>
- [ ] 3.2 Run the existing script sync, registry, marketplace, and dogfood writers so canonical lifecycle sources and installed copies converge (REQ-8, REQ-9, RISK-6, RISK-7) [after: 3.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** plugin-manager bundles, plugin versions, registry, marketplace, README/catalog output, and dogfood copies are generated from the changed canonical sources with no stale retired payload.

  **Likely touchpoints:** `scripts/skalary/{Sync-PluginScripts,Build-Registry,Build-Marketplace,Sync-Dogfood}.ps1`, plugin manifests, `registry.json`, `.github/plugin/marketplace.json`, and `.github/skills/**`.

  **Constraints:** use the existing generator order; never hand-edit generated bundles or catalogs; preserve externally consumed JSON fields unless the direct lifecycle no longer exposes an internal-only field.

  **Verify:** detect-only bundle, registry, marketplace, dogfood, and foreign-consumer drift checks pass.

  </details>
- [ ] 3.3 Run focused direct lifecycle, registry, distribution, and consumer evidence, then one risk-selected whole-plan CR (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7) [after: 3.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** typed deterministic evidence proves the confirmed lifecycle contract and one final direct review covers the complete plan diff without an automatic second model or unchanged-scope rerun.

  **Likely touchpoints:** focused test entry points, plan evidence, and `assets/reviews/final.md`.

  **Constraints:** use the smallest affected test set and no premium eval or full-repository route; any corrective edit invalidates only affected evidence and the final CR.

  **Verify:** every requirement has passing `test:`, `file:`, or `review:` evidence and plan crosscheck succeeds.

  **Stop/escalate when:** deterministic evidence shows unresolved path escape, destructive unforced removal, receipt advancement before verified payload, or external catalog incompatibility; do not wrap those findings.

  </details>
