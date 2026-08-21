# Decisions

<!-- Key decisions made during planning — one bullet per decision. Extended rationale goes in assets/decisions/<topic>.md. -->

- **Test the installed shape, not the source tree.** Consumer fixtures must contain only declared installed payloads and first-use scaffolds.
- **Keep installer confinement.** Rejected: post-install writes outside `.github/`; runtime owners materialize declared scaffolds on first use.
- **Carry Cluster C explicitly.** The invocation cap, plan-size thresholds, and phase-budget default must derive from or be checked against canonical values; this handoff was previously dropped once.
- **Distribution is part of correctness.** Payload, bundles, dogfood, manifests, marketplace, and registry updates are one change, not optional packaging follow-up.
- **Fail loud on undeclared runtime dependencies.** Missing assets or source-tree fallbacks must not degrade into partial consumer behavior.
- **Derive coverage from active manifests.** Rejected: a fixed plugin list or copied source wildcard; additions and retirements must change the required probe set automatically.
- **Use one probe contract per active plugin.** Scripts execute from installed paths; markdown customizations prove parseability and dependency closure; external integrations may return only an exact, bounded, offline prerequisite refusal.
- **Root scanner policy in the grammar.** The declaration-derived root set is self-referential. `tools/runtime-reference-policy.psd1` owns roots, exact resource caps, and persistent exclusions; the plan asset is migration-only and is retired after zero unresolved entries.
- **Keep limits owner-local.** Rejected: one global limits catalog. Plan authoring exposes one structured plan-workflow owner, review reporting exposes one review-schema owner, and the future fleet scheduler owns its concurrency cap; parity tests bind their consumers.
- **Make future consumers declare themselves.** `8a0644` depends on this plan and must register its scheduler-owned cap with parity coverage rather than copying a literal into prose.
- **Keep deterministic tests offline.** No consumer proof requires provider credentials, live GitHub, or network access; prerequisite paths are exact tested outcomes, not skips.
- **Use container whole-plan execution with no new packages.** Existing PowerShell/Pester and repository helpers are sufficient; package or lockfile changes are out of scope.
- **Consume retirement; do not re-own it.** `cda9da` owns tombstones, source identity, preview/apply state, journal/fault behavior, outcomes, and immutable fixture `tests/skalary/fixtures/plugin-retirement/architecture-tests-pre-cda9da-v1/`; this plan owns broad installed-entry-point integration around that settled protocol.
- **One fixture substrate, production installer.** Existing review and retirement fixtures consume the shared snapshot/mutation-copy API or remain explicitly narrower adapters; the shared substrate never reimplements materialization.
- **Use bounded process waves.** Rejected: in-process runspaces and unbounded fan-out. Active plugins run in ordinal waves of four with a 30-second child cap, tier-bound aggregate deadline, allowlisted environment, isolated profiles, removed credential variables, and exact terminal attendance for running and queued probes.
- **Scanner migration is enumerate, disposition, enforce.** Rejected: widening the hard gate in one edit and discovering existing violations only after validation becomes unusable.
- **Depend on `cda9da`.** Retirement identity, inventory, journaling, and legacy policy remain upstream; this plan owns only transition proof from the immutable previous-generation consumer fixture.
- **Use parent-identity rechecks.** Rejected for this plan: a new native handle-relative no-follow abstraction across platforms. Canonical parent identity is checked immediately before mutation; residual TOCTOU is documented for later hardening.
- **CI owns platform authority.** A measurement checkpoint must produce tree-bound Linux and Windows receipts before `met|tier-required` is selected. Container measurements guide implementation but cannot satisfy the platform claim.
- **Split before raising or dropping coverage.** Ordinary aggregate deadlines are 30 seconds Linux/60 seconds Windows; the blocking tier is 120/240 seconds. A tier changes the gate inventory, never coverage or the ordinary ceiling.
- **Confine execute-capable descriptors.** `consumerProbe` entrypoints must resolve to the declaring plugin's own installed `files[].dest`; arguments are closed data passed directly, never shell text. Every scaffold has a one-to-one probe binding and closed parameter cases.
- **Make isolation state recoverable.** Capability preflight is typed and non-pass when unavailable. Any machine-scoped network state is identified durably before activation, reclaimed on startup, and reported after cleanup.
- **Detect copied limits in bounded active roots.** Descriptors register exact consumer paths/fields; owner-value occurrences in active customization/code/note roots require an owner or registration token. Plans, fixtures, goldens, and generated catalogs remain provenance.
- **Keep review v1 validation stable.** `review-limits.schema.json` stores the invocation budget in non-validating `x-skalary-limits.reviewInvocationBudget`; `$defs` and existing frozen fixture semantics do not change.
- **Bind final evidence to its parent.** CI attests the implementation candidate. At most one later evidence-only commit may touch this plan's evidence/review assets and must name the attested parent; it does not relabel its own tree as CI-tested.
- **Raise the advisory phase cap to 12.** Phase 2 is four serial `L` steps because descriptor, complete attendance, scaffold lifecycle, and runtime disposition form one inspectable all-plugin increment; splitting before measurement would leave an unbounded or incomplete matrix.
