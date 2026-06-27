# 7645b1: Optimize /ci and /cip plugins — script-extracted determinism, slimmer skills, anti-drift, date/hash plan naming

<!-- plan-id: 7645b1 -->
<!-- execution-mode: manual -->
<!-- scope: step -->
<!-- evidence: required -->
<!-- phase-budget-points: 6 -->
<!-- cip-stage: dr-round-2 -->

## Decisions

- **Plan identity (new scheme).** Folders use `<yyyy-mm-dd>-<6hex>-<slug>`; the 6-hex `hash` is the stable id, frozen in a `<!-- plan-id: <hash> -->` header anchor and addressable by any unique prefix ≥4 chars (git-short-SHA semantics).
- **Id generation.** `New-PlanId` emits **6 crypto-random hex chars** (no slug/timestamp hashing — ids are intentionally non-reproducible, so a content hash adds no recoverable meaning). It scans active **and** archived ids, regenerates on a full-id collision, and warns when the id is not uniquely addressable at the 4-char minimum prefix. `Repair-Plans` must **never** mutate an existing `plan-id` anchor.
- **Canonical written id.** A plan's id is written into the ledger and `depends-on:` in exactly **one** canonical form (its `plan-id` anchor value: 6-hex for new plans, the 3-digit number for legacy). Callers resolve any reference (prefix/slug/date) to that canonical form via `Resolve-Plan` *before* writing, so dedup/recurrence keys never fork across schemes.
- **Dual-format, no renames.** Legacy `NNN-<slug>` folders keep parsing and stay in place; only new plans use the new scheme. `depends-on:` and the ledger `-Plan` key accept a hash (prefix), a legacy 3-digit number, a slug, or a date — all normalized to the canonical id. Legacy ids are exactly `\d{3}`; hash prefixes are ≥4 chars, so the domains never overlap by length.
- **Parser extraction is a signature change, not verbatim.** `Get-PlanMetadata` (and its private helpers) move into `PlanState.psm1` with an **explicit `-RepoRoot` parameter** (it currently closes over the script-scoped `$RepoRoot`, which a module function cannot inherit under `Set-StrictMode`). All call sites in `Test-Plan.ps1` are updated in the same step; parity is proven with a non-default `-RepoRoot`.
- **Facts-only scripts, agent keeps judgment.** State scripts report facts + flags; the agent still decides `[~]` resume-vs-reset, `@human`/`[discovery]` handling, marker→REQ mapping, and "deferred in Decisions". The slimmed `ci/SKILL.md` must explicitly retain resume/reset, `[~]` marking, and `@human`/`[discovery]` stops.
- **Capture-preserving sanitization via typed params.** `Add-WorkflowNote` emits the structural tokens (`[step:…]`, `[src:…]`, `[sev:…]`, phase header) from **validated typed parameters** (`-Kind`, `-Step`, `-Src`, `-Sev`) and applies sanitization **only to the free-text payload** — escaping/neutralizing brackets, backticks, pipes, `·`, and newlines in the message body so injected markdown/schema-looking text cannot break the line, while the script-emitted schema tokens stay intact. It does **not** reuse `Sanitize-LedgerText` (which strips the very tokens the capture schema needs). `New-Plan` slug input is sanitized and path-confined (canonicalize-then-confine, like `Resolve-LedgerPath`).
- **Shared evidence-receipt grammar (single golden spec).** One canonical receipt line is defined: `✓/✗ REQ-N — <evidence> — <result> — <commit>` (em-dash separators, full HEAD SHA, `✗`/`unrun` block archival). Both `Build-EvidenceReceipt` and the `autopilot.agent.md` crosscheck are tested against the **same golden-line fixture**; preferably autopilot quotes the script's output rather than re-emitting from prose. `Build-EvidenceReceipt` **formats** results (it does not re-verify): it consumes per-marker verifier objects (`Marker`/`Success`/`Blocking`/`Message`) for `file:` markers and records caller-supplied `test:`/`review:` results, aggregating per-REQ against current HEAD.
- **Test-id convention.** Evidence `test:<id>` markers are **single-token, no-space** ids (the `Test-Plan.ps1` marker parser stops at whitespace). For executable scripts the id maps to a Pester tag/`FullName`-filterable test under `tests/skalary/`. For prose `SKILL.md`/agent files, a `test:` id is backed by a `Select-String` assertion that the slimmed file still contains the named structural tokens (an honest guard against the slimming deleting required behavior), and is complemented by `review:cr`/`review:dr`.
- **Anti-drift via a deterministic gate, not just a soft instruction.** Beyond the "run `Get-PlanState` each loop" guidance, the existing Step-5 `validate-plan`/crosscheck gate stays the authoritative reconcile point so displayed state cannot silently diverge from on-disk checkboxes.
- **Checkboxes are the sole `/ci` run state.** No new `/ci` run anchor; `Get-PlanState` is a projection of checkbox parsing. `/cip` keeps `cip-stage`.
- **Size reduction is a best-effort goal, not a gated REQ.** REQs carry functional/behavioral evidence. See `decisions/size-reduction-goal.md`.
- **Design notes updated per contract phase.** Each design-note delta lands in the phase that changes its contract (naming/id → Phase 1; ledger/dependency/receipt → Phase 4; skill flow → Phase 6), per the same-change maintenance protocol.
- **Dogfood discipline.** Edit `plugins/` only; register new/removed assets in `plugin.json` `files[]`; regenerate `.github/skills/` via `Sync-Dogfood.ps1`; the `-WhatIf` drift check is a step gate.
- **Phase-budget override.** Several phases intentionally exceed the advisory 6-point cap: each bundles tightly-coupled deterministic work cheaper to land and review together.

## Requirements

| ID | Requirement | Acceptance Criteria | Phases/Steps |
|----|-------------|---------------------|--------------|
| REQ-1 | `New-PlanId` emits 6 crypto-random hex chars, scans active+archived ids, regenerates on full-id collision, and warns on non-unique 4-char prefix. | `file:scripts/skalary/PlanState.psm1#contains:function New-PlanId` · `test:new-planid-format` · `test:new-planid-collision` | 1.2 |
| REQ-2 | `New-Plan.ps1` scaffolds `<date>-<hash>-<slug>/plan.md` from the template, writes the `plan-id` anchor, and sanitizes + path-confines the slug. | `file:scripts/skalary/New-Plan.ps1#exists` · `test:new-plan-scaffold` · `test:new-plan-traversal` | 1.4 |
| REQ-3 | `Resolve-Plan` resolves a plan from a hash prefix (≥4), a legacy 3-digit number, a slug, or a date; ambiguous prefixes error git-style; all-digit hashes disambiguate from legacy numbers; accepts new + legacy folders; returns the canonical id. | `file:scripts/skalary/PlanState.psm1#contains:function Resolve-Plan` · `test:resolve-plan-hash-prefix` · `test:resolve-plan-legacy-number` · `test:resolve-plan-ambiguous` · `test:resolve-plan-alldigit-hash` | 1.3 |
| REQ-4 | `Get-PlanMetadata` + private helpers move into `PlanState.psm1` with an explicit `-RepoRoot` parameter; all `Test-Plan.ps1` call sites updated; validation behavior preserved under a non-default `-RepoRoot`. | `file:scripts/skalary/PlanState.psm1#contains:function Get-PlanMetadata` · `file:scripts/skalary/Test-Plan.ps1#contains:PlanState` · `test:planstate-parser-parity` · `review:cr` | 1.1 |
| REQ-5 | `Get-PlanProgress` + `Get-PlanHeaderMarkers` report progress counts/current-phase/last-completed and parse header markers (`execution-mode`, `scope`, `cip-stage`, `plan-id`, `depends-on`). | `file:scripts/skalary/PlanState.psm1#contains:function Get-PlanProgress` · `file:scripts/skalary/PlanState.psm1#contains:function Get-PlanHeaderMarkers` · `test:get-planprogress-counts` · `test:get-planheadermarkers` | 2.1 |
| REQ-6 | `Get-NextStep` returns the next candidate plus flags (`isHuman`, `isDiscovery`, `hasUncommittedChanges`, `blockedByAfter`) honoring top-down order + `[after:]`; it does not auto-decide resume/reset or human/discovery handling. | `file:scripts/skalary/PlanState.psm1#contains:function Get-NextStep` · `test:get-nextstep-after` · `test:get-nextstep-flags` | 2.2 |
| REQ-7 | `Get-PlanState.ps1` CLI composes resolve/progress/next-step/markers; prints a human text block by default and a parseable object under `-Json`. | `file:scripts/skalary/Get-PlanState.ps1#exists` · `test:get-planstate-text` · `test:get-planstate-json` | 2.3 |
| REQ-8 | `Add-WorkflowNote.ps1` (`-Kind` one of CrLog, Learnings, Capture) emits schema tokens from typed params (`-Step`/`-Src`/`-Sev`) and sanitizes only the free-text body; does init + append + placeholder-replace; enforces a 10-entry Learnings cap folding the **oldest** entries into a single loud overflow-summary, preserving the fail-loud placeholder contract. | `file:scripts/skalary/Add-WorkflowNote.ps1#exists` · `test:workflownote-init` · `test:workflownote-append` · `test:workflownote-cap` · `test:workflownote-sanitize` | 3.1, 3.2 |
| REQ-9 | `Set-PlanStage.ps1` sets/updates the `cip-stage` anchor idempotently. | `file:scripts/skalary/Set-PlanStage.ps1#exists` · `test:set-planstage` | 3.3 |
| REQ-10 | `Build-EvidenceReceipt.ps1` formats verifier output into the shared golden `✓/✗ REQ-N — evidence — result — commit` grammar (rebuilt, full HEAD SHA, `✗`/unrun preserved); it consumes per-marker `file:` verifier objects and caller-supplied `test:`/`review:` results, aggregating per-REQ. | `file:scripts/skalary/Build-EvidenceReceipt.ps1#exists` · `test:evidence-receipt-format` · `test:evidence-receipt-unrun` | 3.4 |
| REQ-11 | `Repair-Plans.ps1` performs on-demand legacy loose-file migration with `-WhatIf`, idempotent no-op-on-clean, preservation of `depends-on`/worktree markers and existing `plan-id`s, and an archived-plan non-goal. | `file:scripts/skalary/Repair-Plans.ps1#exists` · `test:repair-plans-migrate` · `test:repair-plans-noop` · `test:repair-plans-preserve-id` | 3.5 |
| REQ-12 | Ledger hash-id compatibility (no data loss): the `$Plan` `[ValidatePattern]`, the `ConvertTo-LedgerRecord` regex, the entry-construction string, and the sort/idempotence/recurrence keys all accept `[0-9a-f]{6}` alongside `\d{3}`; a single canonical id is written; a mixed-format file survives append + canonical rewrite with no line lost and no dedup fork. | `file:scripts/skalary/Add-LedgerEntry.ps1#contains:0-9a-f` · `test:ledger-hash-id` · `test:ledger-legacy-id` · `test:ledger-mixed-rewrite` · `test:ledger-dedup-nofork` | 4.1, 4.2 |
| REQ-13 | Dep-006 gate reconciled with slimming: compatibility-anchor tokens that must survive are identified and kept; assertions updated to the slimmed contract; a legacy `006` and a hash-style dependency trigger identical preflight behavior. | `file:scripts/skalary/Test-DependencyPlan006.ps1#contains:Resolve-Plan` · `test:dep006-legacy` · `test:dep006-hash` · `test:dep006-gutted` | 4.3 |
| REQ-14 | ci/cip `SKILL.md` + assets slimmed: capture-schema prose replaced by `Add-WorkflowNote`/`Build-EvidenceReceipt` pointers (placeholder/fail-loud preserved); `/ci` Steps 2 & 4 collapse to a `Get-PlanState` call while explicitly retaining resume/reset, `[~]` marking, and `@human`/`[discovery]` stops; both `SKILL.md` carry the anti-drift contract with the Step-5 validate-plan reconcile gate as authority. Evidence = `Select-String`-backed token guards + review. | `test:ci-skill-retains-judgment` · `test:ci-skill-planstate` · `test:cip-skill-scripts` · `review:cr` | 5.1, 5.2, 5.3 |
| REQ-15 | `autopilot.agent.md` made dual-format-aware: harvest `-Plan`, archive movement, and commit/PR body text resolve the plan id via the canonical scheme (not a raw `NNN`); it emits the shared golden receipt line. Evidence = token guards + golden-line parity + review. | `test:autopilot-plan-id` · `test:autopilot-dual-format` · `review:cr` | 5.4 |
| REQ-16 | Dogfood + manifest integrity: new/removed assets registered in both `plugin.json` `files[]`; `.github/skills/` regenerated; `-WhatIf` drift check passes; npm aliases `plan-state` + `new-plan` invoke the scripts. | `test:dogfood-no-drift` · `file:package.json#contains:plan-state` · `file:package.json#contains:new-plan` · `test:manifest-coverage` | 5.5, 6.1 |
| REQ-17 | Design notes updated in the phase that changes each contract: `plan-workflow.design.md` gains the naming/id + ledger-compat + receipt-grammar + state-script contracts; `copilot-customizations.design.md` reflects the slimmed ci/cip flow. | `file:docs/design-notes/architecture/plan-workflow.design.md#contains:plan-id` · `file:docs/design-notes/architecture/plan-workflow.design.md#contains:PlanState` · `file:docs/design-notes/project/copilot-customizations.design.md#contains:Get-PlanState` · `review:dr` | 1.5, 4.4, 6.2 |

## Risks

| ID | Risk | Likelihood | Impact | Mitigation | Steps |
|----|------|------------|--------|------------|-------|
| RISK-1 | Extracting `Get-PlanMetadata` regresses plan validation (it closes over script-scoped `$RepoRoot`). | High | High | Add an explicit `-RepoRoot` param; update every call site in the same step; gate on existing `ci`/`cip` evals + a parity test using a non-default `-RepoRoot` before proceeding. | 1.1 |
| RISK-2 | Hash plan-ids corrupt the durable ledger: the `\d{3}` parser drops unparsed hash lines on canonical rewrite (silent data loss) and forks dedup keys. | High | High | Treat ledger compatibility as a dedicated REQ-12; co-edit param validator + regex + entry string + all keys; write one canonical id; mixed-format round-trip + dedup-fork regression tests must pass before any orchestrator writes a hash id. | 4.1, 4.2 |
| RISK-3 | Phase-5 slimming drops literal tokens the hard `Test-DependencyPlan006` preflight asserts, failing the gate for every dependent plan. | High | High | Identify compatibility-anchor tokens up front; update gate assertions to the slimmed contract in the same change; test legacy + hash dependencies identically; sequence skill slimming after the gate reconciliation. | 4.3, 5.1, 5.2 |
| RISK-4 | 6-hex id (24-bit) collides at creation or is non-unique at the 4-char prefix. | Medium | High | `New-PlanId` scans active+archived, regenerates on full collision, warns on non-unique prefix; `Repair-Plans` never mutates existing ids. | 1.2 |
| RISK-5 | Reusing the ledger sanitizer on capture text mangles the `[src:][sev:]` schema; an unsanitized slug enables path traversal in `New-Plan`. | Medium | Medium | Emit schema tokens from typed params and sanitize only the free-text body; canonicalize-then-confine slug handling for `New-Plan`; hostile-input tests for both. | 3.1, 1.4 |
| RISK-6 | Slimming the skills silently drops execution-critical behavior (resume/reset, `@human` stops, placeholder/fail-loud contract). | Medium | High | Move (not delete) schema prose into scripts; `Select-String`-backed token-guard tests assert retained behavior; keep `ci`/`cip` structural evals green; `@cr` on slimmed skills. | 5.1, 5.2, 5.3 |
| RISK-7 | Presence-only evidence passes while behavior regresses; space-containing `test:` ids silently truncate in the marker parser. | Medium | Medium | Use no-space `test:` ids backed by real Pester tests for scripts and `Select-String` guards for prose files; round-trip `test:` markers on ledger compat; `contains:` only for genuine presence facts. | 4.1, 5.1 |

## Phase 1: PlanState module foundation + naming
<!-- worktree: agents/optimize-ci-cip-plugins-performance -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) · Points: S=1, M=2, L=3 (advisory cap 6) -->

- [x] 1.1 Move `Get-PlanMetadata` + private helpers into `scripts/skalary/PlanState.psm1` with an explicit `-RepoRoot` param; update all `Test-Plan.ps1` call sites; add a parity test under a non-default `-RepoRoot` (REQ-4, RISK-1) `M`
- [x] 1.2 Add `New-PlanId` (6 crypto-random hex) with active+archived collision scan, regenerate-on-collision, and non-unique-prefix warning, with tests (REQ-1, RISK-4) [after: 1.1] `M`
- [x] 1.3 Add `Resolve-Plan` (hash-prefix ≥4 / legacy number / slug / date; ambiguity + all-digit disambiguation; dual-format; returns canonical id) with tests (REQ-3) [after: 1.1] `M`
- [x] 1.4 Add `New-Plan.ps1` scaffolding `<date>-<hash>-<slug>/plan.md` + `plan-id` anchor with slug sanitization/path-confinement, with tests (REQ-2, RISK-5) [after: 1.2] `M`
- [x] 1.5 Update `plan-workflow.design.md` with the naming/id contract (scheme, canonical id, random-hex id, collision policy, `-RepoRoot` signature change) (REQ-17) [after: 1.3, 1.4] `S`

## Phase 2: State commands (anti-drift anchor)
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 2.1 Add `Get-PlanProgress` + `Get-PlanHeaderMarkers` to `PlanState.psm1` with tests (REQ-5) [after: 1.1] `M`
- [x] 2.2 Add `Get-NextStep` returning next candidate + flags (`isHuman`/`isDiscovery`/`hasUncommittedChanges`/`blockedByAfter`), with tests (REQ-6, RISK-2) [after: 1.1] `M`
- [x] 2.3 Add `Get-PlanState.ps1` CLI (text default + `-Json`) composing resolve/progress/next-step/markers, with tests (REQ-7) [after: 2.1, 2.2] `M`

## Phase 3: Workflow-note, evidence, repair scripts
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 3.1 Add `Add-WorkflowNote.ps1` (`-Kind` CrLog/Learnings/Capture) emitting schema tokens from typed params and sanitizing only the free-text body; init/append/placeholder, with tests (REQ-8, RISK-5) `M`
- [x] 3.2 Add the 10-entry cap folding oldest entries into a single loud overflow-summary, preserving the fail-loud placeholder contract, with tests (REQ-8) [after: 3.1] `S`
- [x] 3.3 Add `Set-PlanStage.ps1` idempotent `cip-stage` writer, with test (REQ-9) `S`
- [x] 3.4 Add `Build-EvidenceReceipt.ps1` consuming per-marker `file:` verifier objects + caller-supplied `test:`/`review:` results, formatting the shared golden `✓/✗ REQ-N …` line (HEAD SHA, unrun/`✗` preserved), with tests (REQ-10) `M`
- [x] 3.5 Add `Repair-Plans.ps1` on-demand legacy migration with `-WhatIf`, idempotent no-op, reference/worktree/`plan-id` preservation, archived non-goal, with tests (REQ-11) `M`

## Phase 4: Ledger + dependency contract (highest risk — gate before wiring)
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 4.1 Widen the ledger to hash ids: co-edit the `$Plan` `[ValidatePattern('^\d{3}$')]`, `ConvertTo-LedgerRecord` regex, the `(plan-$Plan, …)` entry string, and sort/idempotence/recurrence keys to accept `[0-9a-f]{6}` alongside `\d{3}`; add a mixed-format canonical-rewrite no-loss regression test (REQ-12, RISK-2, RISK-7) [after: 1.3] `L`
- [x] 4.2 Enforce one canonical written id via `Resolve-Plan` before any ledger/`depends-on` write; add a dedup-no-fork test across schemes (REQ-12, RISK-2) [after: 4.1] `S`
- [x] 4.3 Reconcile `Test-DependencyPlan006.ps1` with slimming: pin compatibility-anchor tokens, route reference resolution through `Resolve-Plan`, test legacy `006` + hash dependency identically and a gutted-contract negative (REQ-13, RISK-3) [after: 1.3] `M`
- [x] 4.4 Update `plan-workflow.design.md` with the ledger hash-id compatibility + canonical-id + shared receipt-grammar contracts (REQ-17) [after: 4.1, 3.4] `S`

## Phase 5: Slim skills + anti-drift contract + autopilot parity
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 5.1 Rewrite `ci/SKILL.md`: collapse Steps 2 & 4 into a `Get-PlanState` call while explicitly retaining resume/reset, `[~]` marking, and `@human`/`[discovery]` stops; route selection through `Resolve-Plan`; add the anti-drift contract naming the Step-5 validate-plan reconcile gate as authority (REQ-14, RISK-6, RISK-3, RISK-7) [after: 2.3, 4.3] `M`
- [x] 5.2 Slim `ci` assets (`execution-guide.md`, `crosscheck-guide.md`): replace capture/evidence schema prose with `Add-WorkflowNote`/`Build-EvidenceReceipt` pointers (preserve placeholder/fail-loud), demote legacy migration to `Repair-Plans`; keep dep-006 compatibility-anchor tokens (REQ-14, RISK-6, RISK-3) [after: 3.1, 3.4, 3.5, 4.3] `M`
- [x] 5.3 Rewrite `cip/SKILL.md` + slim `drafting-guide.md`/`dr-guide.md`: use `New-Plan`/`Set-PlanStage`, replace capture-schema prose with `Add-WorkflowNote` pointers, document new naming, add anti-drift contract; keep dep-006 anchor tokens (REQ-14, RISK-6) [after: 1.4, 3.1, 3.3, 4.2] `M`
- [x] 5.4 Make `autopilot.agent.md` dual-format-aware: resolve harvest `-Plan`, archive movement, and commit/PR body text via the canonical scheme; emit the shared golden receipt line (REQ-15) [after: 3.4, 4.2] `M`
- [ ] 5.5 Update `plan-template.md` (new title + `plan-id` anchor); register new/removed assets in both `plugin.json` `files[]`; run `Sync-Dogfood.ps1`; `-WhatIf` drift gate passes (REQ-16, RISK-3) [after: 5.1, 5.2, 5.3, 5.4] `M`

## Phase 6: Aliases, design notes, crosscheck
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 6.1 Add npm aliases `plan-state` + `new-plan`; verify they invoke the scripts; add the manifest-coverage test (REQ-16) [after: 2.3, 1.4] `S`
- [ ] 6.2 Update `copilot-customizations.design.md` for the slimmed ci/cip flow + state-script layer; finalize `plan-workflow.design.md` (REQ-17) [after: 5.5] `M`
- [ ] 6.3 Plan crosscheck: rebuild `evidence.md` via `Build-EvidenceReceipt`, run full `npm test` + `npm run eval`, resolve or defer remaining markers (REQ-12, REQ-13, REQ-16, REQ-17) [after: 6.1, 6.2] `S`
