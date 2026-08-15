# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Test the installed shape, not the source tree.** Consumer fixtures must contain only declared installed payloads and first-use scaffolds.
- **Keep installer confinement.** Rejected: post-install writes outside `.github/`; runtime owners materialize declared scaffolds on first use.
- **Carry Cluster C explicitly.** The invocation cap, plan-size thresholds, and phase-budget default must derive from or be checked against canonical values; this handoff was previously dropped once.
- **Distribution is part of correctness.** Payload, bundles, dogfood, manifests, marketplace, and registry updates are one change, not optional packaging follow-up.
- **Fail loud on undeclared runtime dependencies.** Missing assets or source-tree fallbacks must not degrade into partial consumer behavior.
- **Derive coverage from active manifests.** Rejected: a fixed plugin list or copied source wildcard; additions and retirements must change the required probe set automatically.
- **Use one probe contract per active plugin.** Scripts execute from installed paths; markdown customizations prove parseability and dependency closure; external integrations may return only an exact, bounded, offline prerequisite refusal.
- **Root scaffold scanning in the grammar.** The current declaration-derived root set is self-referential. `docs`, `schemas`, and `tools` references are checked even when no plugin declared that root yet.
- **Keep limits owner-local.** Rejected: one global limits catalog. Plan authoring exposes one structured plan-workflow owner, review reporting exposes one review-schema owner, and the future fleet scheduler owns its concurrency cap; parity tests bind their consumers.
- **Make future consumers declare themselves.** `8a0644` depends on this plan and must register its scheduler-owned cap with parity coverage rather than copying a literal into prose.
- **Keep deterministic tests offline.** No consumer proof requires provider credentials, live GitHub, or network access; prerequisite paths are exact tested outcomes, not skips.
- **Use container whole-plan execution with no new packages.** Existing PowerShell/Pester and repository helpers are sufficient; package or lockfile changes are out of scope.
- **Consume retirement; do not re-own it.** `cda9da` owns tombstones, source identity, preview/apply state, journal/fault behavior, outcomes, and immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/`; this plan owns broad installed-entry-point integration around that settled protocol.
- **One fixture substrate, production installer.** Existing review and retirement fixtures consume the shared snapshot/mutation-copy API or remain explicitly narrower adapters; the shared substrate never reimplements materialization.
- **One child process per plugin.** Rejected: in-process runspaces, which share environment, authentication, and network state. Each active plugin gets at most one 30-second process and an exact terminal attendance record.
- **Scanner migration is enumerate, disposition, enforce.** Rejected: widening the hard gate in one edit and discovering existing violations only after validation becomes unusable.
- **Depend on `cda9da`.** Retirement identity, inventory, journaling, and legacy policy remain upstream; this plan owns only transition proof from the immutable previous-generation consumer fixture.
- **Use parent-identity rechecks.** Rejected for this plan: a new native handle-relative no-follow abstraction across platforms. Canonical parent identity is checked immediately before mutation; residual TOCTOU is documented for later hardening.
- **CI owns platform authority.** Final evidence waits for current-tree Linux and Windows CI receipts. Container measurements guide implementation but cannot satisfy the platform acceptance claim.
- **Split before raising or dropping coverage.** If the matrix cannot fit its 30-second Linux/60-second Windows allocation, it becomes a named blocking integration tier with its own ceiling and inventory; it never becomes optional.
- **Raise the advisory phase cap to 12.** Phase 2 is four serial `L` steps because descriptor, complete attendance, scaffold lifecycle, and runtime disposition form one inspectable all-plugin increment; splitting before measurement would leave an unbounded or incomplete matrix.
- **Persist scanner policy outside the plan.** Migration dispositions remain provenance; permanent bounded exclusions and limits are scanner-owned so archival cannot break validation.
- **Use waves of four.** Fast and slow tiers have separate task and aggregate deadlines, and every interruption materializes terminal outcomes for running and unreached probes.
- **Treat evidence as a child of the source tree.** Platform receipts attest `sourceTreeDigest`; a later evidence-only commit is path-confined and must preserve that digest.
- **Keep review defaults non-validating.** Concrete defaults live under `x-skalary-limits`; schema validation bounds remain compatible with published review-run v1 artifacts.
