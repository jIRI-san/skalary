# cda9da: Architecture-test retirement
<!-- plan-id: cda9da -->
<!-- epic: bcece1 -->
<!-- cip-stage: dr-round-3 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 9 -->
<!-- Offline package bundling (autonomous container/sandbox plans): list expected new third-party packages so they can be batched and the offline rebundle round-trip fires at most once. Use `none` when the plan adds no packages. -->
<!-- expected-packages: none -->

## Assets

`plan.md` holds only the markers above, this index, and the phases/steps below. Everything else lives under `assets/` and is loaded on demand — never wholesale.

- Intent — [assets/intent.md](assets/intent.md)
- Requirements — [assets/requirements.md](assets/requirements.md)
- Risks — [assets/risks.md](assets/risks.md)
- Decisions — [assets/decisions.md](assets/decisions.md) (extended rationale in `assets/decisions/<topic>.md`)
- References — [assets/references.md](assets/references.md)
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Freeze baselines and decouple preserved authority
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Before destructive edits, commit immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/` containing the current bootstrap/plugin-manager installer scripts, registry entry, receipt, installed payload, manifest scaffolds, and approval-key inventory; commit `tests/skalary/fixtures/plugin-retirement/cda9da-historical-manifest.json` with starting commit plus every bounded archived-plan/transcript/report path and SHA256, and prove nonzero count, per-path rehash, listed-file mutation failure, and empty-manifest failure. Add plugin-owned `Get-ArchContractContentHash.ps1` as the sole canonical JSON projection/UTF-8 hashing owner excluding only `lockedContentSha256`; update canonical/shipped schemas, write gate, surviving fixtures/evals/dogfood, and a repository-wide contract-integrity sweep in `scripts/validate.ps1` to require correct locked digests while documenting human promotion as reviewer-enforced policy rather than machine-authenticated identity (REQ-4, REQ-5, REQ-6, RISK-5, RISK-7) `L`
- [x] 1.2 Before removing any evaluator, tokenize every marker-shaped occurrence independently and preserve generic unknown-prefix refusal; add exact mixed `test:`/`file:`/`review:`/`arch:` Draft and PhaseCrosscheck tests with seeded-red/empty-root cases across the manifest-derived CI/CIP/CEP/CR/DR/PFB/SI bundles; then remove `arch:` evaluator/import code from `PlanEvidence.psm1`, synchronize that full closure, and update architecture-notes skill/templates/review, `architecture-notes.design.md`, `plan-workflow.design.md`, tier indexes, human-doc generator, old-scaffold schema-version upgrade-or-refuse behavior, plus `ci-gates.design.md` to add `gate:architecture-contract-integrity` under `scripts/validate.ps1` and remove `gate:architecture-tests`/`exclusion:arch-tier-not-seeded` (REQ-3, REQ-4, REQ-5, REQ-6, RISK-4, RISK-5, RISK-6) [after: 1.1] `L`
- [x] 1.3 Add and prove the generic catalog mechanism without publishing a real tombstone: closed `schemas/registry/plugin-retirement.schema.json`, empty canonical `registry-retirements.json`, generated skalary-registry `retiredPlugins` only, active/retired disjointness, direct retired-target lookup, and pure-file `Test-PluginRetirementHistory.ps1 -BaselinePath -CandidatePath`; add a dedicated blocking step to `.github/workflows/registry-ci.yml` plus exact `gate:plugin-retirement-history` inventory/invocation checks, where a resolvable base with no file means empty set, PR/push SHAs are explicit, unresolved required base fails, and output records baseline identity/count; keep `Test-Registry` git-free and prove first publication, changed/removed record, name reuse, and unavailable-base cases (REQ-2, REQ-6, RISK-4, RISK-6) [after: 1.2] `L`

## Phase 2: Prove existing-consumer retirement mechanism
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add one versioned credential-free source-identity API shared by install/update/receipt writes/retirement, with canonical GitHub repository identity, hashed local-source identity, separate immutable ref, legacy ambiguity refusal, and sentinel-secret tests; add plugin-name-validated, confine-resolved, schema-validated `.github/.skalary/retirements/<name>.json` state for preview/applying/retired/residue/failed, persisting the complete affected path/hash set plus prior source/ref/version while capping emitted output only (REQ-7, REQ-8, RISK-1, RISK-2) [after: 1.3] `L`
- [ ] 2.2 Extract one journaled removal primitive for explicit `Remove-Plugin` and automatic retirement; update `ARCH-Install-Confinement` and `arch-install-confinement.md`; under the existing mutation lock reject traversal/rooted/reparse destinations and parents before any state read/stat/journal/backup/prune, re-confine every state path, rederive every apply set as the exact intersection of tombstone-pinned source/ref/version destination hashes and the current same-source receipt, validate untrusted journal identity/shape/confinement/backup hashes, scope recovery to recorded plugin/source, fail closed on mixed-version pre-state mismatch, support failed-to-preview retry only after exact recovery, and keep modified files plus degraded receipt ownership intact (REQ-5, REQ-7, REQ-8, RISK-2, RISK-3, RISK-8) [after: 2.1] `L`
- [ ] 2.3 Wire install/update and bootstrap exit propagation before active-name lookup and every no-op return; prove the exhaustive outcome table in `retirement-protocol.md`, require exact matching preview before apply, automatically refresh stale preview with zero deletion while explicit stale apply fails, emit at most one bounded aggregate `RETIREMENT:` record, and process terminal residue/manual work with a global limit of 8 plugins and 64 paths per invocation plus persisted fair cursor, stat-without-hash, and eventual-remedy replay; cap process coverage at four shared-fixture subprocesses with one timeout and one representative hard-kill while keeping state/fault/hostile-path/journal matrices in-process, all against synthetic tombstones only (REQ-7, REQ-8, RISK-1, RISK-2, RISK-3, RISK-8) [after: 2.2] `L`

## Phase 3: Publish architecture-tests retirement and delete subsystem
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Atomically add the real `architecture-tests` tombstone with immutable known payload sets keyed by normalized source/ref/version, plus `manualResidue` entries derived from its scaffolds, Copilot CLI location, and `.vscode` approval keys with exact manual remedies; delete plugin source, tracked dogfood payload, root runner/module/adapter/review scripts, config/receipt schemas, runtime tests/evals/convention/profile/exclusion entries, and solely here delete `architecture-tests.design.md`, its design-note-index row, `DesignNotes` assertions, and every surviving active runtime cross-reference; regenerate registry/README/dogfood/suite outputs while leaving the Copilot marketplace tombstone-free (REQ-1, REQ-2, REQ-5, REQ-6, REQ-7, RISK-4, RISK-6, RISK-8) [after: 2.3] `L`
- [ ] 3.2 Prove the real immutable fixture lifecycle: old installer does not claim cleanup; first capable operation previews; stale automatic preview refreshes; later operation retires only the pinned intersection; clean/residue/foreign/manual/recovered results follow the outcome table; direct retired target exits distinctly; root/CLI/approval residue is repeatedly reported but never automatically mutated; and fresh consumers cannot acquire any runtime asset (REQ-1, REQ-2, REQ-7, REQ-8, RISK-1, RISK-2, RISK-3, RISK-8) [after: 3.1] `L`

## Phase 4: Cross-plan reconciliation and full proof
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Extend `plugin-registry.design.md` with the permanent protocol and document preview/apply plus pinned-ref recovery; update `34088e` step 4.1, REQ-5, decisions, and references to consume exact fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/` and retain only broad installed-entry-point integration; rehash every starting historical-manifest path and use include-rooted active scans with seeded violations, without deleting or rewriting historical artifacts (REQ-5, REQ-6, REQ-7, REQ-8, RISK-6, RISK-7, RISK-8) [after: 3.2] `M`
- [ ] 4.2 Refresh suite profile/coverage/runtime metadata only through canonical generators; require exact discovery of every evidence ID in this plan including `test:PluginCatalog.GeneratedArtifacts`; stay under existing Windows/Linux `suite-budget.psd1` ceilings with four-process cap/shared timeout asserted; run focused catalog/history/reconciliation/removal/confinement/schema/integrity/marker/preservation checks and then full deterministic unit/validation plus structural evals, finishing with clean bundle, registry, marketplace, README, dogfood, architecture-human-doc, starting-history-manifest, and payload drift checks (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, RISK-3, RISK-4, RISK-6, RISK-7) [after: 4.1] `L`
