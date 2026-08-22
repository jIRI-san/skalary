# 2366ad: Cross-repo si and review standards
<!-- plan-id: 2366ad -->
<!-- cip-stage: done -->
<!-- depends-on: 1936cb, 34088e, 79cfe1 -->
<!-- epic: 33b1f9 -->
<!-- Folder naming: <yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- evidence: required -->
<!-- phase-budget-points: 12 -->
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

## Phase 0: Dependency contract gate
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 0.1 Verify `1936cb`, `34088e`, and `79cfe1` are complete or archived; resolve their indexed SI state, trusted sync, workflow-limit, consumer-install, concern-registry, and generator contracts; write `assets/dependency-receipts/<sha256>.json` plus a superseding current pointer through `Test-DependencyContracts.ps1`, with closed changed/missing/unreadable exits and phase-2/phase-4 restart semantics. (REQ-1, RISK-1) `M`
- [ ] 0.2 Add the typed evidence-id registry, schema, and attendance validator before creating new evidence: one owner kind per id (Pester group, structural eval, runner gate, aggregate gate, or review), at least one executed assertion for test ids, no duplicate owner, and zero skipped/unrun required outcomes. (REQ-17, RISK-11) [after: 0.1] `M`

## Phase 1: Derived cross-repo projection
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 In canonical `plugins/self-improvement/{schemas,scripts}/`, define projection, handoff-result, limits, and scope-receipt schemas plus writers over `1936cb` state; add `ARCH-Si-Cross-Repo-Transport`, the self-improvement design-note update, explicit plugin source-to-`skills/si/{schemas,scripts}` mappings, version/dogfood closure, and focused JCS, 64 KiB/4 KiB, redaction, identity, closed-exit, sole-owner, no-second-store, and hostile-content tests in the same change. (REQ-2, REQ-3, REQ-4, REQ-7, REQ-15, RISK-1, RISK-2, RISK-3, RISK-11) [after: 0.2] `L`
- [ ] 1.2 Extend the canonical SI state writer with an exact writable-leaf manifest and session-wide before/after scope receipt, one verified fenced projection reader, idempotent projection/import correlation, metadata-only fingerprint persistence, foreign-source transitions, and snapshot-paged digest-memoized history; prohibit direct inbox reads and unauthorized in-root/steering writes while preserving existing CAS, archive/prune, repair, and immutable disposition. (REQ-2, REQ-3, REQ-6, REQ-7, REQ-14, REQ-15, RISK-1, RISK-2, RISK-3, RISK-6) [after: 1.1] `L`
- [ ] 1.3 Run detect-only plugin mapping/bundle/dogfood/architecture drift, installed foreign-consumer execution, sole-writer/absence scans, unauthorized in-root mutation fixtures, maximum-history seams, and the registered focused evidence for Phase 1. (REQ-15, REQ-17, RISK-11) [after: 1.2] `M`

## Phase 2: Upstream-rooted handoff and proposal
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Revalidate the dependency receipt, then add plugin-canonical checkout/cache/limits/inventory-repair scripts and docs: receipt-only GitHub target derivation with pre-network `unresolvable-target`, one machine-owned testable root, sanitized Git, immutable generations, 120-second clone/60-second fetch, 10 GiB and 4-generation target cap, 2 GiB/7-day quarantine, 30-second lock, 100-entry/10-second reclaim, 240-second aggregate handoff, source/run/candidate branch identity, inventory/purge/release modes, isolated test root, and complete installed/architecture closure. (REQ-1, REQ-4, REQ-5, REQ-7, REQ-15, RISK-4, RISK-5, RISK-6, RISK-11) [after: 1.3] `L`
- [ ] 2.2 Add the plugin-owned confined importer/verified reader and isolated-container launcher rooted only at the disposable upstream checkout; attest root and upstream instructions, exclude consumer tree/user profiles, return typed handoff on isolation failure, name one credentialed trusted-sync publish call, and prove zero network/root creation on identity refusal plus no consumer bytes/paths or credentials in diffs, prompts, commands, policy inputs, author/reviewer processes, or checkout files. (REQ-3, REQ-5, REQ-6, REQ-7, REQ-8, REQ-15, RISK-2, RISK-4, RISK-5, RISK-6, RISK-11) [after: 2.1] `L`
- [ ] 2.3 Extend `/si` routing to scan claimed source fingerprints in 64-record pages up to 4,096 records/8 MiB/10 seconds with 256 memo entries across active and archived immutable history; emit typed incomplete corroboration on limits, persist metadata before every non-failed cleanup, route authority/large changes to correlated `/cip` plans, require durable plan publication, record all terminal follow-ups, and register every authority path in the executable SI deny set. (REQ-4, REQ-7, REQ-8, REQ-14, REQ-15, RISK-3, RISK-5, RISK-6, RISK-11) [after: 2.2] `L`
- [ ] 2.4 Run detect-only installed/design/architecture closure and the Slow matrix for cold cache, poisoned generation, Git canaries, local/legacy/malformed receipt, source/target mismatch, branch collision, reparse/escape, every plus-one limit, reclaim/crash/replay, isolation/root attestation, exact-run scope, evidence/credential leak, stale head, durable decline/no-op/plan cleanup, inventory/purge, and foreign-consumer execution; remeasure Slow headroom against a captured pre-change baseline. (REQ-5, REQ-7, REQ-8, REQ-15, REQ-17, RISK-4, RISK-5, RISK-6, RISK-11) [after: 2.3] `L`

## Phase 3: Typed generic and local review standards
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Extend `79cfe1`'s authoritative concern registry/schema/template/inventory and `Sync-ReviewConcerns.ps1` so one validated source authors agents and the generated runtime standards inventory atomically; bind all 14 pre-edit blobs/criteria, define permanent STD/LOCAL tombstones, 96+32 capacity, `optionalInputs` plugin/registry/asset-scanner support for consumer-owned `docs/review-standards.md`, and land generator/manifests/version/dogfood/design-note/eval closure with omission/deletion and generated-Markdown drift tests. (REQ-9, REQ-10, REQ-13, REQ-16, RISK-7, RISK-9, RISK-11) [after: 0.2] `L`
- [ ] 3.2 Implement canonical `scripts/skalary/Resolve-ReviewStandards.ps1`, bundle byte-identical CR/DR copies, and enforce trusted-base bootstrap/admission inputs: first adoption derives frozen authority from the base OID and bound generated-agent digests; later runs use generated inventory. Cap each source at 128 KiB, combined rule/rationale at 1,536 bytes, generic/local totals at 96/32, each concern/review type at 24 rules/48 KiB/12K estimated tokens, the shared generation at 336 KiB, and resolution at 5 seconds. (REQ-10, REQ-11, REQ-13, REQ-16, RISK-7, RISK-9, RISK-11) [after: 3.1] `L`
- [ ] 3.3 Complete resolver/install/design closure and focused matrices for bootstrap versus later self-exemption, generic-only, local extension/replace/suppress, immutable promotion mapping, malformed/duplicate/retired/dangling/asymmetric rows, hostile text, every 96+32/per-dispatch/14-task fan-out plus-one, token-estimator version, timeout, optional-input absence/preservation, and canonical/generated drift. (REQ-9, REQ-10, REQ-11, REQ-16, REQ-17, RISK-7, RISK-10, RISK-11) [after: 3.2] `L`

## Phase 4: CR and DR standards enforcement
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Revalidate the dependency receipt, capture exact maximum-envelope arithmetic first, then atomically add review-run v2 plus `ARCH-Review-Run-V2`: one deduplicated `standards-generation.<sha256>.json` manifest role/store, engine-owned standards admission reasons/exits/replay/cleanup/Get-ReviewRun integration, per-task digest/override references, at most four finding rule IDs, 3,584-byte finding bodies, unchanged 2 MiB input/view budgets, v1 readers, vocabulary/maxima/corpus/goldens/capability/interoperability, complete schema/bundle/install/dogfood/design/human-doc closure, and semantic architecture-field tests. (REQ-1, REQ-11, REQ-12, REQ-16, RISK-8, RISK-11) [after: 3.3] `L`
- [ ] 4.2 Atomically adopt standards in code-review through the extended concern generator: prove complete baseline mapping, freeze trusted-base bootstrap authority, switch `/cr` admission/freeze/dispatch, regenerate seven agents without normative duplicates, register authority paths, retire CR ledger-consult-as-review guidance, update full manifests/version/dogfood/docs/evals, and pass installed-consumer, ledger-exclusion, architecture-precedence, hostile-input, publication-tamper, citation, and evidence-attendance tests in the same change. (REQ-10, REQ-11, REQ-12, REQ-13, REQ-16, REQ-17, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11) [after: 4.1] `L`
- [ ] 4.3 Atomically adopt the same contract in design-review: prove mapping, freeze bootstrap authority, switch `/dr`, regenerate seven agents, register authority paths, retire DR/CI/autopilot review-ledger dispatch guidance while retaining ledger promotion evidence and CIP planning consult, update full closure, and pass parity, asymmetric authority, citation, v1/v2, tamper, hostile-input, structural-eval, and final frozen migration-fixture tests. (REQ-10, REQ-11, REQ-12, REQ-13, REQ-16, REQ-17, RISK-7, RISK-8, RISK-9, RISK-10, RISK-11) [after: 4.2] `L`

## Phase 5: Promotion, distribution, and documentation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 5.1 Finalize immutable promotion follow-ups for `adopted`, `declined-upstream`, `withdrawn`, `superseded`, and `failed`, each chaining prior receipt, claimed-source corroboration digest, candidate, and correlated plan; update authority precedence, consumer ownership, protected paths, and `/cip` delivery guidance without changing behavior-owner contracts. (REQ-8, REQ-14, REQ-15, RISK-3, RISK-7, RISK-10) [after: 2.4, 4.3] `M`
- [ ] 5.2 Run detect-only documentation/architecture convergence and retire implemented explorations: update `docs/design-notes/.design-notes.md`, `docs/design-notes/explorations/explorations-and-experiments.design.md`, `docs/architecture-notes/.architecture-notes.md`, `docs/architecture-notes/architecture.human.md`, review-enforcement Cluster F/G status, and owning self-improvement/review-reporting/plugin-registry/plugin-evals/CI/plan-workflow/customization notes; remove the two exploration files only after rationale is present in owning notes. (REQ-15, REQ-16, RISK-11) [after: 5.1] `M`

## Phase 6: Final integration gates
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Run the typed evidence registry/attendance gate, detect-only payload/generator/bundle/dogfood/architecture drift, generate marketplace and registry once inputs converge, then run all focused SI/standards/v2 matrices, Slow process suites, complete Fast/unit and structural eval gates, installed-consumer validation, architecture freshness, limits/runtime budgets, and repository validation. (REQ-17, REQ-18, RISK-11) [after: 5.2] `M`
- [ ] 6.2 Run final branch code review under v2 frozen standards authority, fix in-scope findings, rerun affected focused and final gates, and leave typed evidence ready for plan crosscheck. (REQ-18) [after: 6.1] `M`
