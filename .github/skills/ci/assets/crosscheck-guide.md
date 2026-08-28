# Crosscheck Guide (`ci` Step 5)

> Read this asset when validating phase/plan completion and proving requirements with typed evidence.

## Evidence verification

At phase and plan crosschecks, verify each requirement's typed markers from Acceptance Criteria:

- `test:<TestId>` -> invoke the existing focused Fast runner with explicit `-TestPath`, batched `-EvidenceTestId <TestId[]>`, and `-EvidenceResultPath`; consume the structured results. Missing, failed, skipped, unrun, or degraded output is not passed, and a nonzero runner exit remains blocking even when one selected record passed.
- `file:<path>#<assertion>` -> verify via `.github/skills/ci/scripts/Test-Plan.ps1 -EvidenceMarker ... -EvidenceStage <PhaseCrosscheck|PlanCrosscheck>` (delegates to the dot-sourceable `PlanEvidence` callable).
- `review:cr|dr` -> verify the relevant review run reports no remaining findings for the claimed class; treat "no review run" as unrun evidence (fail the gate).

Use deterministic, pre-approvable commands only. Parse markers into typed variables and pass them as bound arguments (no shell-string interpolation, no eval). Use `PlanCrosscheck` only at true finalization.

Build the receipt with the shared formatter — do not hand-write receipt lines. `Build-EvidenceReceipt.ps1` is a **pure formatter**: it takes per-marker verifier results as `-Result` objects (each carrying `Req`, `Marker`, one closed `Status`, and an optional `Note`; legacy `Success` remains accepted) plus the current `-Commit`. It returns an object whose `.Text` you write into the receipt and never executes evidence. Pass `-PlanDir` and write to the returned `.ReceiptPath` — it resolves through `Resolve-PlanAssetPath` to `assets/evidence.md` in the current layout and to the plan-folder root `evidence.md` for legacy plans:

```powershell
# $results = array of [pscustomobject]@{ Req='REQ-1'; Marker='test:foo'; Status='passed'; Note='' } ...
$receipt = & .github/skills/ci/scripts/Build-EvidenceReceipt.ps1 -Result $results -Commit <HEAD-sha> -Phase <N> -PlanDir <plan-folder>
Set-Content -LiteralPath $receipt.ReceiptPath -Value $receipt.Text -Encoding utf8NoBOM
```

`Build-EvidenceReceipt` emits the golden line `<glyph> REQ-N — <marker> — <result> — <commit>`: `✓ passed`, `⊘ waived`, and `✗` for `failed`, `skipped`, `unrun`, `stale`, or `degraded`. A REQ passes only when all markers passed or carry an exact valid plan-local waiver.

The optional layout-resolved waiver file is `assets/evidence-waivers.json` (legacy: `evidence-waivers.json`) with schema `skalary/evidence-waivers@1`. Every entry must bind the canonical `plan`, exact `requirement`, exact declared `marker`, source `outcome` (`skipped` or `degraded`), non-empty `reason`, and optional `platform` (`Windows`, `Linux`, or `MacOS`). Wildcards and waivers for failed, unrun, or stale evidence are rejected. The formatter renders a valid match as visibly `waived`; it never renders it as passed.

Receipt rules:
- The receipt path is layout-resolved (`assets/evidence.md`, or the plan-folder root for legacy plans) — always take it from `$receipt.ReceiptPath`, never hard-code it.
- Rebuild the receipt on each phase/plan crosscheck run (never append to stale results from old commits).
- Emit one line per required marker; unexecuted markers emit `✗ … — unrun`.
- Use the current `HEAD` commit SHA in every emitted line.
- At finalization, write the receipt, run `Test-Plan -Stage PlanCrosscheck`, then commit. The gate accepts the parent source only when the current commit changes that receipt alone; any other later change makes it stale and requires rebuilding.

## Phase crosscheck

The root-canonical harvest engine is distributed at
`.github/skills/ci/scripts/Invoke-PhaseHarvest.ps1`; its generated closure includes
`LedgerStore.psm1`, `PlanState.psm1`, and `AtomicStore.psm1`.
The bound scalar compatibility entry point remains installed at
`.github/skills/ci/scripts/Add-LedgerEntry.ps1`; it delegates to the same `LedgerStore.psm1`
engine and is not a second harvest implementation.

1. Re-anchor against the plan's intent asset (`assets/intent.md`, or the plan-folder root for legacy plans — resolve with `Resolve-PlanAssetPath`). Re-read the goal, desired outcome, success signals, non-goals, and definition of done, and state for the phase just finished whether the delivered work still serves them. Typed evidence proves the requirements were met; only intent tells you the phase met the point. Record any drift as a finding (`Add-WorkflowNote -Kind Learnings -Trigger plan-contradiction -Concern architecture-patterns -Requirement <REQ-N...> -ReviewType none`) before declaring the phase complete.
2. Collect REQ IDs referenced by steps in the current phase.
3. Validate each acceptance criterion against implementation + typed evidence checks (`test:`/`file:`/`review:`). Keep execution focused on the phase's affected surface and named evidence.
4. After all phase implementation, fixes, and focused checks are complete, run one **Fast** gate selected from the files and behavior changed in this phase. It must target only the highest-signal relevant tests. In this repository invoke `Run-UnitTests.ps1 -Tier Fast -TestPath <repo-relative-test-files> [-TestName <Pester-full-name-filters>]` through a bound argument array; `-TestName` is required when the owning file belongs to Slow. Never use `npm test`, `scripts/validate.ps1`, `-FullRepository`, or an unfiltered **Slow** suite at a phase boundary. `OverBudget`, `StaleMeasurement`, and `BudgetNotDefined` are advisory: report them, but never change budgets, runtime rows, implementation, or scope, and never rerun solely because of them. A failed assertion or nonzero correctness gate may be retried only after corrective changes; any later implementation change invalidates the successful run and requires one replacement run before phase completion.
5. Build the review scope as the union of repo-relative implementation, test, and directly related documentation paths changed by this phase's completed step commits. Exclude plan progress and ephemeral log-only paths. If the exact phase union cannot be recovered, use `branch` scope rather than silently omitting files.
6. Run the review loop below with stage `phase-<N>` and invoke `@cr post-phase <phase-paths-or-branch>`. The profile is primary-model only; apply clear findings and re-run the focused phase checks before the next round.
7. Invoke the installed `.github/skills/ci/scripts/Invoke-PhaseHarvest.ps1` through a bound argument array with `-PlanDir <plan-folder> -Phase <N> -Src ci -RepoRoot .`. `complete` and `empty` are the only completion outcomes. Re-run the phase harvest when it returns `degraded` or `capacity-blocked`; if it remains unresolved, surface that status explicitly and stop phase completion. Finalization only replays receipts that already exist.
8. On `complete` or `empty`, stage the returned receipt path plus only the ledger category files changed by the harvest, then commit them before phase completion. Skip the commit only when replay produced no git delta.
9. Rebuild the receipt via `Build-EvidenceReceipt` (with `-PlanDir`) at the current commit SHA and write it to `.ReceiptPath`.
10. Fail phase completion if blocking criteria are unsatisfied.

## Plan crosscheck

1. Re-anchor against the plan's intent asset: confirm the delivered plan satisfies the operator's definition of done and success signals, and that no non-goal was silently taken on. Unresolved intent drift is a gap, not a rounding error — record it explicitly.
2. Run final project validation only after every implementation phase is complete. Full-repository validation must use the repository's explicit opt-in parameter. In this repository run `npm test` only after confirming its committed `test:unit` leg contains `Run-UnitTests.ps1 -Tier Fast -FullRepository`; then run the Slow suite exactly once (`npm run test:slow`). Never infer full scope from an omitted parameter or bypass the complete configured command. A failed final gate may be retried only after corrective changes.
3. After every implementation phase is complete, run the review loop below with stage `plan-finalization` and invoke `@cr plan-finalization branch`. This is the only primary + secondary execution review and must cover the whole implementation. Apply clear findings and re-run complete project validation before the next round.
4. Validate all REQ and RISK rows before completion.
5. Ensure unresolved gaps are explicitly deferred in Decisions if not fixed.
6. Re-run typed evidence checks at plan scope (`PlanCrosscheck` stage) at true finalization.

## archival-gate

Before archive/PR completion, require:
- The layout-resolved receipt (`assets/evidence.md`, or root `evidence.md` for legacy plans) exists and is current.
- `Test-Plan.ps1 -Stage PlanCrosscheck` passes against the current receipt. It re-derives every required marker, rejects stale or malformed lines, and revalidates exact waivers.
- No required marker is failed, skipped, unrun, stale, or degraded; only passed and exact waived lines satisfy the gate.

If the gate is not satisfied, block archival/completion.

### Post-plan feedback (`/pfb`) — offered, never blocking

Typed evidence proves the requirements were met; only the operator can say whether the delivered work
met the point. Archiving is the last moment anyone looks at the plan, so offer `/pfb` here — and only
offer it. It is not a gate condition: a declined or unanswered `/pfb` never blocks archival or the PR,
and a recorded verdict never substitutes for a `✗` marker.

1. Skip silently when the `self-improvement` plugin is not installed (`Test-Path .github/skills/pfb/SKILL.md`).
2. Interactive completion: offer the `/pfb` run before the archive commit. If the operator accepts,
   read `.github/skills/pfb/SKILL.md` by path and run it against the completing plan, then commit
   `docs/feedback/queue.md` by explicit path where harvest item 4 places it — before branch
   selection, so the `@human` escalation branch (which never makes an archive commit) still commits
   it. If they decline, continue.
3. Headless completion has no operator to ask: the autopilot mirror queues the question instead of
   prompting, and the next interactive session consumes the queued marker. Never answer on the
   operator's behalf in either direction.

### Self-improvement (`/si`) — offered after the ledger is written, never blocking

`/pfb` records what the operator thought; `/si` is what reads the records back. Offer it at plan
completion, **after the harvest step has run** — the entries this plan just wrote are part of the
corpus it harvests, and offering earlier would read a ledger that is one plan out of date. Ordering,
not a commit, is the precondition: a no-op harvest that produced no append commit still leaves the
ledger current, and an infra-absent run that skipped harvest entirely can still offer `/si` if the
skill is installed.

1. Skip silently when the `self-improvement` plugin is not installed (`Test-Path .github/skills/si/SKILL.md`).
2. Before offering, invoke dependency-installed `.github/skills/si/scripts/Invoke-SiLifecycle.ps1`
   through a bound argument array with `-Operation Surface -RepoRoot .`. It fetches and pins
   `origin/main`, classifies fixed `si/<due-id>` and `si-repair/<observation-id>` branches, and
   returns only closed metadata: IDs, statuses, timestamps, OIDs, and outcome counts. Never open SI
   state/run files directly. Surface eligible pending dues, in-flight/resumable work, deferred-until
   dates, declined-before-ranking/no-candidate outcomes, completed disposition counts, and integrity
   states before the offer. A script failure is explicit non-blocking degradation: report it, do not
   claim SI state was surfaced, and continue plan completion without ranking partial state.
3. Interactive completion: offer the run. On acceptance, read `.github/skills/si/SKILL.md` by path
   and follow it. `/si` produces a ranked candidate list and, only with explicit operator consent, a
   **draft** PR on a worktree branch cut from `origin/main` — never from the plan's branch, whose
   diff would otherwise land in the proposal's scope and be refused by the pre-PR guard. It never
   merges, never pushes to `main`, and never commits into the plan's branch.
4. Headless completion does not run `/si`. The harvest is cheap; a proposal is not — it opens a PR
   against the repo's own instructions with nobody to have asked. Queue nothing and skip.
5. It is never a gate: a decline, an empty harvest, or a refused write-scope check blocks neither
   archival nor the PR.
6. **Consumer repos are manual.** `/si` proposes into the repository it runs in, and in a consumer
   repo the customizations arrive through the registry — an improvement made there is overwritten by
   the next update. Carry the candidate list upstream by hand: fork `skalary`, apply the change, and
   open the PR there. The fork/upstream round-trip is deliberately not automated; `gh` fork
   entitlement is out of scope.

## Dependency preflight (hard start-gate)

For plans declaring `<!-- depends-on: <id> -->`, run this deterministic non-Pester check at plan start and again immediately before any interactive harvest/finalization branch:

```powershell
pwsh -NoProfile -File .github/skills/ci/scripts/Test-DependencyPlan006.ps1 -RepoRoot . -PlanPath <selected-plan-path>
```

It resolves the dependency through `Resolve-Plan` and validates the 006 behavior contracts through public script paths (pass/fail `file:` probes, evidence vocabulary, the `test:unit` gate, and pinned compatibility-anchor tokens). If it exits non-zero, stop execution immediately.

## Interactive harvest trigger (`/ci`) — mirror of canonical autopilot flow

This section is a **mirror** of the canonical harvest procedure in `plugins/autopilot/agents/autopilot.agent.md`. Keep parity with that file whenever harvest behavior changes.

At interactive plan completion, `/ci` runs harvest with the same shared scripts and ordering:

1. Run dependency preflight (`Test-DependencyPlan006.ps1`) before entering harvest/finalization.
2. If append infra is present (`Test-Path .github/skills/ci/scripts/Invoke-PhaseHarvest.ps1`), execute append harvest first:
   - Invoke `.github/skills/ci/scripts/Invoke-PhaseHarvest.ps1` through a bound argument array with `-PlanDir <plan-folder> -FinalSweep -Src ci -RepoRoot .`. Finalization replays immutable phase receipts and never redistills logs.
   - `complete` and `empty` are the only completion outcomes. Surface `degraded` or `capacity-blocked` explicitly and stop before branch selection or archival.
   - Stage and commit ledger updates by explicit file names under `docs/review-ledger/`.
   - If harvest is idempotent/no-op with no staged ledger delta, skip the append commit and continue to branch selection.
3. **ADR harvest (when the `architecture-notes` plugin is installed).** So architectural decisions made during `/cip` + `/ci` become reviewable records, harvest the plan's decision records into proposed ADRs via the arch-notes **adr-harvest** operation: `Import-ArchAdr.ps1 -PlanDir <plan-folder> -RepoRoot .` (from its install). Pass the plan folder, not the decisions folder — the script resolves `assets/decisions/` for the current layout and `decisions/` for legacy plans. ADRs land quarantined (`reviewed: false`, under `docs/architecture-notes/.staging/adr/`) and are **not** auto-loaded until a human promotes accepted ones into the index's Decision Records (active) table. Commit staged ADRs by explicit path. Skip silently if the plugin is not installed.
4. **Post-plan feedback (`/pfb`), offered before archiving and never blocking.** Offer the `/pfb` run against the completing plan; on acceptance, read `.github/skills/pfb/SKILL.md` by path, run it, and commit `docs/feedback/queue.md` by explicit path. A decline, or a `self-improvement` plugin that is not installed, skips it silently. See the `archival-gate` section above — the offer never gates archival or the PR.
5. **Self-improvement (`/si`), surfaced after this harvest step and never blocking.** Invoke dependency-installed `Invoke-SiLifecycle.ps1 -Operation Surface` with bound arguments first; it fetches/pins `origin/main` and returns metadata-only due/run/fixed-branch state. Report explicit degradation and skip ranking when Surface fails. Then offer the `/si` run once harvest has run — whether or not it produced an append commit — so the lessons this plan just wrote are in the corpus it reads. On acceptance, read `.github/skills/si/SKILL.md` by path and follow it; it ranks candidates and, only with explicit consent, opens a **draft** PR on a worktree branch cut from `origin/main` — never a merge, never a push to `main`, never a branch off the plan's branch (its diff would land in the proposal's scope and the pre-PR guard would refuse). A decline, an absent `self-improvement` plugin, or an empty harvest skips it silently. Headless completion does not run it: a proposal nobody asked for is a PR against the repo's own instructions. Consumer repos carry candidates upstream by hand — see the `/si` section above.
6. Branch after the append commit:
   - Autonomous completion: push, archive commit, **required post-archive push**, create non-draft PR.
   - `@human` escalation: push, run `/udn` reconciliation with the user present first, derive full-line prune candidates, run `Remove-LedgerEntry.ps1`, commit prune/design-note edits, push, create draft PR, write marker, stop.
   - `/udn` contract: run deterministic reconciliation prompts/checks; if ambiguity remains, keep the draft-PR + marker path (no archive).
   - Prune preconditions: `Test-Path .github/skills/ci/scripts/Remove-LedgerEntry.ps1` and `Test-Path docs/review-ledger/.archive`; if missing, skip prune and continue direct draft escalation.
   - Invoke `Remove-LedgerEntry.ps1` via argument arrays / `ArgumentList` only; always pass `-Category`, `-CurrentPlan`, and full-line candidate match payload (`-Match`/`-MatchBase64`) — never substring/regex targeting.
7. If repo infra is absent, skip harvest and keep branch semantics explicit: autonomous completion may continue standard completion flow, but `@human` completion must still route to draft PR + marker (no archive).

Fail-loud behavior: error only when expected log sections/placeholders are missing; `No entries for this phase.` is valid and must not fail harvest.

## `ledger-consult` (before a CR round)

Before launching a CR round (`@cr`, `code-review`, or `rubber-duck`), consult only the relevant category files from `docs/review-ledger/`:

Every `/ci`-launched CR round is gated by
`.github/skills/ci/scripts/ReviewCycleGate.ps1`: use stage `phase-<N>` for the primary-only
post-phase review and `plan-finalization` for the primary + secondary whole-implementation review.
Before dispatch, run `-Action Check`. On `allow`, dispatch the selected profile. Persist every finding
and triage through `Add-WorkflowNote -Kind CrLog`, then run
`-Action Record -Outcome <clean|findings> -Summary <bounded-counts-and-run-id>`. On
`operator-decision`, do not run a fourth review
automatically: use `vscode_askQuestions` with exactly **Continue looping** and **Wrap up**. Continue
authorizes one additional round; Wrap retains residual findings and never produces clean evidence.
The automatic cap is three rounds independently for each stage.

- `security.md` — auth/trust-boundary/injection/secret/ACL
- `performance.md` — latency/throughput/allocation/N+1
- `error-handling.md` — retry/timeout/fail-loud/exception-flow
- `consistency.md` — contract drift/naming parity/duplication
- `plan-structure.md` — dependency gates/phase order/evidence-flow
- `testing.md` — flaky/missing/weak evidence coverage
- `observability.md` — logs/metrics/tracing/audit

Rules: exclude `docs/review-ledger/.archive/`; read only categories implied by the active phase or
plan-finalization REQ/RISK scope; optionally filter by `#tag`; never auto-load all ledger files by default.

## Ephemeral capture (`cr-log.md` / `learnings.md`, mid-run only)

Capture is mid-run, plan-folder-local, and **script-only** via `Add-WorkflowNote.ps1` — do not hand-edit these files and do not write `docs/review-ledger/*` during capture. `Add-WorkflowNote` resolves the log path itself (`assets/logs/<file>` in the current layout, plan-folder root for legacy plans), so pass `-PlanDir` and never a file path:

- Initialize a phase section (header + `No entries for this phase.` placeholder) by calling `Add-WorkflowNote` with no `-Message`.
- `cr-log.md` (`-Kind CrLog`): interactive `ci` persists `@cr` report + triage; autopilot persists `code-review`/`rubber-duck` findings with `-Src code-review`; standalone `cr` persists nothing.
- `learnings.md` (`-Kind Learnings`): append only on `rework>1`, `plan-contradiction`, or `reusable-pattern` triggers, with typed concern/REQ/review provenance. The script keeps 10 active entries and writes older records to layout-resolved content-addressed overflow batches before replacing the active file. Old `overflow-summary` lines return explicit `legacy-loss` degradation.
- Stage and commit the changed log by explicit filename.

Fail-loud: missing required sections/placeholders fail; an intentionally empty `No entries for this phase.` section stays valid.
