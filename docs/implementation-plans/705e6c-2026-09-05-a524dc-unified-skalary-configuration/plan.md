# a524dc: Unified Skalary configuration
<!-- plan-id: a524dc -->
<!-- depends-on: 367e9a, 33a78a, 3a4498, 623cc2 -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:d31a7b382638e4396afa5240ed6be33e794199a4ee662e5227ba0ccd5e27b375 -->
<!-- epic: 705e6c -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
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
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Catalog and read-only flow
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add the `skalary-config` plugin shell and the closed human-readable configuration catalog for every accepted category and current source/generated/precedence boundary (REQ-1, REQ-9, RISK-1, RISK-2, RISK-5) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the canonical plugin contains a compact `/skalary-config` entrypoint and a catalog row for
  each accepted category, including its canonical/default/generated paths, precedence, sensitivity,
  bootstrap behavior, writer or synchronizer, focused validator, and installed-consumer availability.

  **Likely touchpoints:** `plugins/skalary-config/**`, plugin registry sources, configuration design notes,
  and focused catalog fixtures.

  **Constraints:** keep the catalog as readable Markdown; do not add manifest declarations, a registry
  schema, or a second source of truth. Unsupported surfaces must be named rather than guessed.

  **Verify:** `test:SkalaryConfig.Catalog` and `file:plugins/skalary-config/plugin.json#exists`.

  </details>

- [x] 1.2 Implement confined read-only discovery, effective-value resolution, validation, current-diff, and mutation preview with secret redaction and source-change detection (REQ-2, REQ-3, REQ-7, RISK-1, RISK-3, RISK-6) [after: 1.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** guided and direct `show`, `validate`, `diff`, and proposal paths resolve source versus
  installed layouts, explain precedence, emit one category-scoped secret-redacted proposal, and write
  nothing. A preview carries only an in-memory source digest so Apply can refuse stale input.

  **Likely touchpoints:** skill instructions, a small read-only skill-local script/module, catalog assets,
  and fixture repositories covering source, installed, missing-optional, dirty, and unsupported layouts.

  **Constraints:** accept no arbitrary target path; never read credential values; do not persist a
  proposal, receipt, or runtime state. Host-equivalent complex choices retain context, examples, benefits,
  pros/cons, effort, and complexity.

  **Verify:** `test:SkalaryConfig.ReadOnly` and `test:SkalaryConfig.Preview`.

  **Stop/escalate when:** a listed effective value cannot be derived from an active canonical source or
  shipped example without inventing precedence.

  </details>

## Phase 2: Safe routine mutation
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add lazy bootstrap, secret-setup handoff and validation, edit, Apply/Cancel, and per-key reset for autopilot and local review standards while preserving unknown and unrelated content (REQ-3, REQ-4, REQ-7, REQ-8, REQ-10, RISK-3, RISK-4, RISK-6, RISK-9, RISK-10) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the selected category alone can be bootstrapped from its current shipped example, edited,
  or reset by key after preview; Cancel is byte-clean; Apply refuses a changed source digest, writes only
  canonical files, validates executable settings, and reports the final diff. Autopilot setup prints
  source-specific token acquisition, permission, storage, and login instructions; after the operator
  completes them in a separate shell and selects Ready to validate, a secret-safe wrapper runs the
  existing credential and authentication probes and reports only availability and capabilities.

  **Likely touchpoints:** `.autopilot*.json` examples and schemas, optional
  `docs/review-standards.md`, autopilot credential/auth scripts, bounded skill-local mutation helpers,
  setup guidance, and isolated mutation fixtures.

  **Constraints:** preserve unknown JSON/Markdown content and unrelated keys. Build/test/host commands and
  container extensions require an explicit extra warning. Context defaults to `default`;
  `long_context` requires a cost warning and explicit advanced selection. Token values never enter
  prompts, command arguments, logs, diffs, or output; validation failure stops with exact remediation.

  **Verify:** `test:SkalaryConfig.Mutation`, `test:SkalaryConfig.Autopilot`, and
  `test:SkalaryConfig.AutopilotAuth`.

  **Stop/escalate when:** the existing file is malformed, linked, outside the repository, or cannot be
  changed without rewriting unrelated operator content.

  </details>

- [x] 2.2 Add one complete model-routing proposal across aliases, host bindings, roles, fallbacks, effort, context, autopilot, CR/DR, and Waza consumers (REQ-5, REQ-7, REQ-8, RISK-2, RISK-6, RISK-8, RISK-9) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the model category shows and edits the six stable aliases and every role assignment in
  `tools/model-allowlist.psd1`; Apply runs `Sync-ModelBindings.ps1` and the existing focused model/Waza
  checks so generated skill assets, agent bindings, Waza executor/judge slugs, and dogfood stay converged.

  **Likely touchpoints:** model allowlist and sync scripts, generated binding consumers, autopilot
  defaults, Waza specs, model tests, and cost guidance.

  **Constraints:** one alias proposal updates one authority; concrete generated bindings are never edited
  independently. Invalid alias, host, role/fallback, effort, or context combinations fail before write.
  Reset restores shipped role defaults and `default` context without removing advanced opt-in support.

  **Verify:** `test:SkalaryConfig.Models` and `test:SkalaryConfig.ModelSynchronization`.

  **Stop/escalate when:** an active model consumer is not represented by the canonical allowlist or
  existing synchronizer.

  </details>

## Phase 3: Remaining categories and failure closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Route terminal approvals, eval credentials/specs, note scaffolds, and advanced plugin/toolchain policy through their existing owners (REQ-4, REQ-6, REQ-7, RISK-2, RISK-3, RISK-5, RISK-7) [after: 1.2] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** the façade covers every remaining accepted category: exact read-only terminal approvals;
  credential-target availability and Waza settings; design/architecture scaffold status and owner
  commands; and clearly separated advanced manifest, eval-pin, and toolchain policy.

  **Likely touchpoints:** `Set-ScriptApproval.ps1`, `.eval.config.json.example`, Waza YAML, note scaffold
  scripts, plugin manifests, tool pins, skill assets, and category fixtures.

  **Constraints:** reuse direct subsystem commands. Refuse mutating or secret-bearing auto-approval,
  credential values, workflows, generated catalogs/dogfood, runtime/plan state, receipts, retirement
  history, and architecture lock promotion. Advanced paths remain unavailable in installed-consumer mode
  when maintainer sources or tools are absent.

  **Verify:** `test:SkalaryConfig.Categories` and `test:SkalaryConfig.Safety`.

  **Stop/escalate when:** an existing owner cannot preview or validate a requested mutation without
  exposing a secret or bypassing its confinement boundary.

  </details>

- [ ] 3.2 Make Apply sequencing and failure reporting category-bounded, fail-loud, and recoverable from the visible Git diff without claiming rollback (REQ-3, REQ-7, REQ-8, RISK-2, RISK-3, RISK-4, RISK-6) [after: 2.1, 2.2, 3.1] `L`
  <details><summary>Implementation contract</summary>

  **Outcome:** each Apply rechecks the preview digest, changes canonical sources, runs only required
  synchronizers and focused validators in documented order, then reports success and the final diff.
  Write, sync, or validation failure returns non-success, leaves the actual diff visible, and prints the
  exact direct recovery command.

  **Likely touchpoints:** skill-local apply orchestration, existing synchronizers/validators, failure
  fixtures, and operator-facing output.

  **Constraints:** no broad rollback, journal, backup, retry service, or success-shaped fallback. A
  category cannot widen into another category during Apply.

  **Verify:** `test:SkalaryConfig.Failures`, including cancellation, stale preview, write failure, sync
  failure, validation failure, and generated-source refusal.

  </details>

## Phase 4: Distribution and closure
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Publish the plugin through existing bundle/registry/marketplace/dogfood generators and document the unified façade without replacing direct subsystem guidance (REQ-1, REQ-6, REQ-9, RISK-1, RISK-2, RISK-5, RISK-7) [after: 3.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the canonical plugin, installed `.github` copy, registry, marketplace, README catalog,
  operator guide, architecture/design notes, and direct configuration links agree; uninstalling the
  plugin removes only the façade and leaves every underlying configuration path usable.

  **Likely touchpoints:** `plugins/skalary-config/**`, `registry.json`,
  `.github/plugin/marketplace.json`, `.github/skills/skalary-config/**`, `README.md`,
  `docs/operator-guide/**`, and the new configuration design note.

  **Constraints:** use `Sync-PluginScripts.ps1`, `Build-Registry.ps1`,
  `Build-Marketplace.ps1`, and `Sync-Dogfood.ps1`; never hand-edit generated outputs.

  **Verify:** `test:SkalaryConfig.ConsumerInstall`, `test:SkalaryConfig.Distribution`, and
  `file:docs/design-notes/architecture/skalary-config.design.md#exists`.

  </details>

- [ ] 4.2 Run the closed focused contract matrix, prove excluded-surface residue is absent, and complete one final review of the delivered façade (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, RISK-1, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7, RISK-8, RISK-9, RISK-10) [after: 4.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** focused plugin/configuration tests, model/Waza checks, registry and dogfood drift checks,
  installed-consumer fixtures, and active-source residue assertions pass; one terminal CR covers the
  complete plan scope.

  **Likely touchpoints:** focused Pester suites, structural eval registration, distribution checks, and
  final review evidence.

  **Constraints:** do not run an ordinary full repository sweep. Any missing accepted category,
  unredacted secret, direct generated write, arbitrary path, central config authority, or stale
  source/generated mapping blocks completion. Autopilot auth fixtures must prove instructions for each
  supported auth/provider path, separate-shell resume, real validation-script composition, redacted
  output, and failure remediation without using live secrets.

  **Verify:** `test:SkalaryConfig.Final`, `test:SkalaryConfig.ConsumerInstall`, and `review:cr`.

  </details>
