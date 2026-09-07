# 7ce29c: Script surface cleanup and simplification
<!-- plan-id: 7ce29c -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:e65e3921c20bb7f7816ad0d5b1bb8ac5e65007f94d2931c5de0f43abbfb92f39 -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: host-autopilot -->
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

## Phase 1: Retire proven dead and historical script machinery
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Delete unused wrappers and the completed plan-folder migration as one closed cut (REQ-1, REQ-2, RISK-1) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the three unused wrappers and the migration script/test are absent, with no dangling
  active reference; current registry validation, review consumer tests, plan creation, plan resolution,
  and archived plan discovery remain.

  **Likely touchpoints:** `scripts/skalary/{Invoke-PluginRetirementHistoryGate,Test-PluginRetirementHistory,Test-ReviewConsumerInstall,Migrate-PlanFolderPrefixes}.ps1`,
  `tests/skalary/Migrate-PlanFolderPrefixes.Tests.ps1`, and any migration-only references.

  **Constraints:** delete rather than deprecate; do not repair or replace the migration; keep
  `ReviewConsumerInstall.Tests.ps1`, current retirement-catalog shape validation, and new prefixed plan
  creation.

  **Verify:** focused residue checks plus current registry, review-consumer, `New-Plan`, and plan-resolution
  tests.

  **Stop/escalate when:** an active manifest, skill, operator guide, or supported command is found to
  invoke one of the candidates; retain that candidate and report the concrete consumer.

  </details>
- [x] 1.2 Replace the architecture-test historical snapshot with a current active-surface absence test (REQ-3, RISK-2) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** the 34-file historical baseline subsystem is gone and one readable test protects against
  reintroduction of the retired architecture-test plugin, commands, schemas, and active design note.

  **Likely touchpoints:** `tests/skalary/ArchitectureRetirementBaseline.Tests.ps1`,
  `tests/skalary/fixtures/plugin-retirement/**`, `scripts/skalary/Test-HistoricalManifest.ps1`, and a
  focused current-state retirement test.

  **Constraints:** scan an explicit bounded list of active roots; exclude archived plans and Git history;
  do not retain copied retired code, byte manifests, a generic history gate, or generated inventories.

  **Verify:** seed representative retired paths/symbols into an isolated fixture to prove detection, and
  prove the real active roots are clean.

  **Stop/escalate when:** a current test relies on the old fixture for behavior other than proving
  historical byte identity; identify that behavior before deleting the fixture.

  </details>

## Phase 2: Remove the architecture human-document compatibility chain
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Delete generated human-doc production, freshness, distribution, and consumer-fixture machinery (REQ-4, RISK-3, RISK-6) [after: 1.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** architecture notes have one human-readable representation—authoritative Markdown—and no
  generator, digest marker/helper, generated document, freshness gate, template, manifest mapping, or
  compatibility-specific consumer fixture remains.

  **Likely touchpoints:** `docs/architecture-notes/architecture.human.md`,
  `plugins/architecture-notes/scripts/{New-ArchHumanDoc,Get-ArchContractsHash}.ps1`,
  `scripts/skalary/Test-ArchDocFreshness.ps1`, the human-doc template, architecture-notes manifest/evals,
  `tests/ConsumerInstallFixture.psm1`, `scripts/validate.ps1`, and generated registry/dogfood files.

  **Constraints:** preserve `Test-ArchContract.ps1`, remaining JSON contract validation, Markdown seed,
  ADR import, staging/promotion rules, and `/uan`; do not replace the human document with another
  generated representation.

  **Verify:** focused architecture-note evals prove Markdown scaffold/update behavior and direct legacy
  JSON validation with no compatibility-view path.

  **Stop/escalate when:** direct validation of the remaining JSON contract depends inseparably on the
  digest helper; extract only the minimum local validation behavior instead of retaining generation.

  </details>
- [x] 2.2 Rewrite architecture-note contracts and guidance for the Markdown-only result (REQ-4, REQ-9, RISK-3) [after: 2.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** both architecture indexes, the architecture-notes design note, plugin skill, and operations
  guide describe Markdown as the sole human-readable source and mention no temporary human-doc workflow.

  **Likely touchpoints:** `docs/architecture-notes/.architecture-notes.md`,
  `docs/design-notes/architecture/architecture-notes.design.md`,
  `plugins/architecture-notes/skills/architecture-notes/**`, and their generated copies.

  **Constraints:** distinguish removal of the generated view from removal of the remaining JSON contract;
  keep active ADR and validation semantics concise.

  **Verify:** active-document residue search finds no removed file or command names, and plugin evals
  exercise every retained architecture-note operation.

  </details>

## Phase 3: Simplify large active modules in place
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Reduce epic-autopilot private machinery while preserving orchestration outcomes (REQ-6, REQ-9, RISK-4, RISK-5, RISK-7) [after: 2.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `EpicAutopilot.psm1` has fewer than 44 private functions and fewer than 2,083 non-comment
  lines while still exporting only `Invoke-EpicAutopilotHostLoop` and preserving its tested state,
  admission, launch, merge, evidence, recovery, replay, and concurrency behavior.

  **Likely touchpoints:** `scripts/skalary/EpicAutopilot.psm1`,
  `tests/autopilot/EpicAutopilot.Tests.ps1`, and generated autopilot copies.

  **Constraints:** start from caller/branch evidence; prefer deletion and local merging of one-use helpers;
  do not remove runtime modes or safety checks, compress statements, strip useful comments, or extract a
  new production module.

  **Verify:** parser-based structural evidence and the smallest complete EpicAutopilot test selection.

  **Stop/escalate when:** both metrics cannot decrease without weakening a supported behavior or guard;
  stop with the candidate inventory rather than gaming the threshold.

  </details>
- [x] 3.2 Reduce work-hierarchy private machinery while preserving projection and apply semantics (REQ-7, REQ-9, RISK-4, RISK-5, RISK-7) [after: 3.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `WorkHierarchy.psm1` has fewer than 19 private functions and fewer than 1,636 non-comment
  lines while retaining the exact 16 exported functions and current deterministic projection, mapping,
  provider, dry-run, refusal, confirmation, checkpoint, and apply behavior.

  **Likely touchpoints:** `scripts/skalary/WorkHierarchy.psm1`,
  `tests/skalary/{WorkHierarchy,WorkHierarchyConsumerInstall}.Tests.ps1`, and generated plugin copies.

  **Constraints:** preserve the narrow provider boundary and concurrency/revalidation guarantees; merge
  duplicate local parsing/validation paths only when their error semantics remain explicit; no new
  production module.

  **Verify:** parser-based structural evidence plus projection, GitHub adapter,
  dry-run/confirmation/apply, and installed-consumer tests.

  **Stop/escalate when:** a reduction would weaken remote-change refusal, mapping confinement, durable
  successful-prefix recovery, or deterministic serialization.

  </details>
- [x] 3.3 Reduce direct-workflow private machinery while preserving shared review and evidence semantics (REQ-8, REQ-9, RISK-4, RISK-5, RISK-7) [after: 3.2] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `DirectWorkflow.psm1` has fewer than eight private functions and fewer than 708 non-comment
  lines while retaining the exact seven exported functions and current criteria-baseline, report,
  standards, untrusted-framing, and live-evidence behavior.

  **Likely touchpoints:** `scripts/skalary/DirectWorkflow.psm1`,
  `tests/skalary/DirectWorkflow*.Tests.ps1`, direct workflow consumers, and generated copies.

  **Constraints:** preserve `ARCH-Direct-Workflow`, Git clean-filter comparison, physical report
  confinement, secret redaction, complete-task verdicts, and current-only evidence; no new production
  module.

  **Verify:** parser-based structural evidence plus direct workflow core and consumer tests.

  **Stop/escalate when:** simplification would combine security-sensitive framing/confinement with
  unrelated logic or alter an exported contract.

  </details>

## Phase 4: Converge distributions and prove the reduced surface
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 4.1 Update affected design notes and run existing owned generators (REQ-1, REQ-4, REQ-5, REQ-9, RISK-6) [after: 3.3] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** architecture/design notes describe the reduced implementation; plugin manifests, registry,
  marketplace, README/catalog output, and `.github` dogfood contain no removed payload and carry the
  simplified canonical modules; `clean-sandbox-cache.ps1` remains installed.

  **Likely touchpoints:** affected notes and indexes, plugin manifests,
  `scripts/skalary/{Sync-PluginScripts,Build-Registry,Build-Marketplace,Sync-Dogfood}.ps1`,
  `registry.json`, `.github/plugin/marketplace.json`, and `.github/skills/**`.

  **Constraints:** use existing generator order; never hand-edit generated copies or catalogs; avoid
  documenting implementation details that the cleanup deletes.

  **Verify:** detect-only sync/catalog/dogfood checks and explicit retained-cleaner checks pass.

  </details>
- [ ] 4.2 Run focused cleanup, architecture, module, distribution, and consumer evidence followed by one whole-plan CR (REQ-1, REQ-2, REQ-3, REQ-4, REQ-5, REQ-6, REQ-7, REQ-8, REQ-9, RISK-2, RISK-3, RISK-4, RISK-5, RISK-6, RISK-7) [after: 4.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** deterministic evidence proves the deleted surface stays absent, retained behavior and
  exports are unchanged, every module beats both structural baselines, generated output is converged,
  and one final review finds no relocation, compressed-code metric gaming, or stale compatibility path.

  **Likely touchpoints:** focused Pester entry points, parser-based structure test, generator detect-only
  modes, plan evidence, and `assets/reviews/final.md`.

  **Constraints:** use the smallest combined affected test set; no premium eval, live GitHub smoke, or
  routine full-repository suite; a corrective edit invalidates only affected evidence and the final CR.

  **Verify:** every requirement has passing typed evidence and plan crosscheck succeeds.

  **Stop/escalate when:** any exported function changes, a retained safety boundary loses coverage, a
  module misses either reduction threshold, or generated/consumer evidence cannot converge.

  </details>
