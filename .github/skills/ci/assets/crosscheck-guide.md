# Crosscheck Guide (`ci` Step 5)

> Read this asset when validating phase/plan completion and proving requirements with typed evidence.

## Evidence verification

At phase and plan crosschecks, verify each requirement's typed markers from Acceptance Criteria:

- `test:<TestId>` -> run only the named Pester test and fail if it is missing or failing.
- `file:<path>#<assertion>` -> verify via `.github/skills/ci/scripts/Test-Plan.ps1 -EvidenceMarker ... -EvidenceStage <PhaseCrosscheck|PlanCrosscheck>` (delegates to the dot-sourceable `PlanEvidence` callable).
- `arch:<ContractId>` -> verified by the same validator: `Invoke-PlanArchEvidence` PURE-PARSES the contract's integrity/freshness receipt (never runs a toolchain), rejecting a missing/stale/malformed receipt and mapping the recorded verdict through the taxonomy x maturity gate (`locked`: only a real `pass` greens; `fail`/`error`/`skip` block; `draft`/`provisional` warn; `semantic-eval` advisory-always).
- `review:cr|dr` -> verify the relevant review run reports no remaining findings for the claimed class; treat "no review run" as unrun evidence (fail the gate).

Use deterministic, pre-approvable commands only. Parse markers into typed variables and pass them as bound arguments (no shell-string interpolation, no eval). Use `PlanCrosscheck` only at true finalization.

Build the receipt with the shared formatter — do not hand-write receipt lines. `Build-EvidenceReceipt.ps1` is a **pure formatter**: it takes the per-marker verifier results as `-Result` objects (each carrying `Req`, `Marker`, `Success`, and an optional `Note`) plus the current `-Commit`, and returns an object whose `.Text` you write into the receipt (the script itself does not read or write the receipt file). Pass `-PlanDir` and write to the returned `.ReceiptPath` — it resolves through `Resolve-PlanAssetPath` to `assets/evidence.md` in the current layout and to the plan-folder root `evidence.md` for legacy plans, so the receipt is never written where the archival gate does not look:

```powershell
# $results = array of [pscustomobject]@{ Req='REQ-1'; Marker='test:foo'; Success=$true; Note='' } ...
$receipt = & .github/skills/ci/scripts/Build-EvidenceReceipt.ps1 -Result $results -Commit <HEAD-sha> -Phase <N> -PlanDir <plan-folder>
Set-Content -LiteralPath $receipt.ReceiptPath -Value $receipt.Text -Encoding utf8NoBOM
```

`Build-EvidenceReceipt` emits the golden line `<glyph> REQ-N — <marker> — <result> — <commit>` (`✓` pass, `✗` fail/unrun); a REQ passes only when all its markers pass, and failed/unrun markers are preserved.

Receipt rules:
- The receipt path is layout-resolved (`assets/evidence.md`, or the plan-folder root for legacy plans) — always take it from `$receipt.ReceiptPath`, never hard-code it.
- Rebuild the receipt on each phase/plan crosscheck run (never append to stale results from old commits).
- Emit one line per required marker; unexecuted markers emit `✗ … — unrun`.
- Use the current `HEAD` commit SHA in every emitted line.

## Arch-tests receipts (opt-in real run)

An `arch:<ContractId>` marker pure-parses a receipt; the receipt is produced by the **arch-tests runner**, which
is the ONLY component that shells a real toolchain (`dotnet test`/`vitest`). Running it is **opt-in**, homed here
in `/ci` implementation/crosscheck exactly like the eval harness's `-IncludeLlm` — never in `scripts/validate.ps1`
or `npm test`, which stay dependency-free/structural and only pure-parse the committed receipts.

When a step touches a `locked` contract (or at a crosscheck that must refresh a stale receipt), regenerate the
receipt with the runner, then commit it alongside `evidence.md`. The runner lives in the **`architecture-tests`
plugin** (it carries the adapters/providers + lock authority a real run needs, which are plugin-owned and not
bundled into `ci`); invoke it only when that plugin is installed:

```powershell
# requires the architecture-tests plugin installed; $archSkill is its installed skill dir,
# i.e. architecture-tests under the .github/skills install root (NOT bundled into ci).
$archSkill = Join-Path '.github/skills' 'architecture-tests'
pwsh -NoProfile -File (Join-Path $archSkill 'scripts/Invoke-ArchTests.ps1') -ConfigPath <arch-test-config.json> -RepoRoot .
```

The runner installs frozen (`npm ci --ignore-scripts` / `dotnet restore --locked-mode`), runs only human-reviewed
`locked` bodies behind the lock gate, and writes a taxonomy verdict into `docs/architecture-notes/receipts/`. The
`arch:` marker (above) then verifies that receipt by pure parse — no toolchain runs at verification time.
**Containment is honest:** `--ignore-scripts` disables install-lifecycle scripts only — `vitest`/`dotnet test`
still execute third-party framework/dev-dep code (and MSBuild targets) in-process, so real runs execute in the
documented **non-containing sandbox**, not a true container.

## Phase crosscheck

1. Re-anchor against the plan's intent asset (`assets/intent.md`, or the plan-folder root for legacy plans — resolve with `Resolve-PlanAssetPath`). Re-read the goal, desired outcome, success signals, non-goals, and definition of done, and state for the phase just finished whether the delivered work still serves them. Typed evidence proves the requirements were met; only intent tells you the phase met the point. Record any drift as a finding (`Add-WorkflowNote -Kind Learnings -Trigger plan-contradiction`) before declaring the phase complete.
2. Collect REQ IDs referenced by steps in the current phase.
3. Validate each acceptance criterion against implementation + typed evidence checks (`test:`/`file:`/`review:`).
4. Rebuild the receipt via `Build-EvidenceReceipt` (with `-PlanDir`) at the current commit SHA and write it to `.ReceiptPath`.
5. Fail phase completion if blocking criteria are unsatisfied.

## Plan crosscheck

1. Re-anchor against the plan's intent asset: confirm the delivered plan satisfies the operator's definition of done and success signals, and that no non-goal was silently taken on. Unresolved intent drift is a gap, not a rounding error — record it explicitly.
2. Validate all REQ and RISK rows before completion.
3. Ensure unresolved gaps are explicitly deferred in Decisions if not fixed.
4. Re-run typed evidence checks at plan scope (`PlanCrosscheck` stage) at true finalization.

## archival-gate

Before archive/PR completion, require:
- The layout-resolved receipt (`assets/evidence.md`, or root `evidence.md` for legacy plans) exists and is current.
- No unrun or failing required evidence (`✗`) remains unless explicitly deferred in Decisions (defer by REQ ID with rationale).
- This step wires the gate only; run `PlanCrosscheck` blocking target resolution only at true plan finalization (after all phases).

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
2. If append infra is present (`Test-Path .github/skills/ci/scripts/Add-LedgerEntry.ps1` and `Test-Path docs/review-ledger`), execute append harvest first:
   - Require category files (at minimum `docs/review-ledger/security.md` and `docs/review-ledger/testing.md`) before invoking append scripts.
   - Distill entries from the layout-resolved logs — `assets/logs/{capture,cr-log,learnings}.md`, or the plan-folder root for legacy plans. Resolve with `Resolve-PlanAssetPath`; reading the wrong location yields a silently empty harvest.
   - Map candidates deterministically into `Add-LedgerEntry` inputs: `-Category` from the 7-category rubric, `-Plan` the canonical plan id, `-Src ci`, `-Severity` from captured severity (default `Med`), `-Entry` one sanitized lesson, `-Tags` sorted tags.
   - Invoke `Add-LedgerEntry.ps1` via argument arrays / `ArgumentList` only (no shell-string interpolation).
   - Stage and commit ledger updates by explicit file names under `docs/review-ledger/`.
   - If harvest is idempotent/no-op with no staged ledger delta, skip the append commit and continue to branch selection.
3. **ADR harvest (when the `architecture-notes` plugin is installed).** So architectural decisions made during `/cip` + `/ci` become reviewable records, harvest the plan's decision records into proposed ADRs via the arch-notes **adr-harvest** operation: `Import-ArchAdr.ps1 -PlanDir <plan-folder> -RepoRoot .` (from its install). Pass the plan folder, not the decisions folder — the script resolves `assets/decisions/` for the current layout and `decisions/` for legacy plans. ADRs land quarantined (`reviewed: false`, under `docs/architecture-notes/.staging/adr/`) and are **not** auto-loaded until a human promotes accepted ones into the index's Decision Records (active) table. Commit staged ADRs by explicit path. Skip silently if the plugin is not installed.
4. **Post-plan feedback (`/pfb`), offered before archiving and never blocking.** Offer the `/pfb` run against the completing plan; on acceptance, read `.github/skills/pfb/SKILL.md` by path, run it, and commit `docs/feedback/queue.md` by explicit path. A decline, or a `self-improvement` plugin that is not installed, skips it silently. See the `archival-gate` section above — the offer never gates archival or the PR.
5. Branch after the append commit:
   - Autonomous completion: push, archive commit, **required post-archive push**, create non-draft PR.
   - `@human` escalation: push, run `/udn` reconciliation with the user present first, derive full-line prune candidates, run `Remove-LedgerEntry.ps1`, commit prune/design-note edits, push, create draft PR, write marker, stop.
   - `/udn` contract: run deterministic reconciliation prompts/checks; if ambiguity remains, keep the draft-PR + marker path (no archive).
   - Prune preconditions: `Test-Path .github/skills/ci/scripts/Remove-LedgerEntry.ps1` and `Test-Path docs/review-ledger/.archive`; if missing, skip prune and continue direct draft escalation.
   - Invoke `Remove-LedgerEntry.ps1` via argument arrays / `ArgumentList` only; always pass `-Category`, `-CurrentPlan`, and full-line candidate match payload (`-Match`/`-MatchBase64`) — never substring/regex targeting.
6. If repo infra is absent, skip harvest and keep branch semantics explicit: autonomous completion may continue standard completion flow, but `@human` completion must still route to draft PR + marker (no archive).

Fail-loud behavior: error only when expected log sections/placeholders are missing; `No entries for this phase.` is valid and must not fail harvest.

## `ledger-consult` (before a CR round)

Before launching a CR round (`@cr`, `code-review`, or `rubber-duck`), consult only the relevant category files from `docs/review-ledger/`:

- `security.md` — auth/trust-boundary/injection/secret/ACL
- `performance.md` — latency/throughput/allocation/N+1
- `error-handling.md` — retry/timeout/fail-loud/exception-flow
- `consistency.md` — contract drift/naming parity/duplication
- `plan-structure.md` — dependency gates/phase order/evidence-flow
- `testing.md` — flaky/missing/weak evidence coverage
- `observability.md` — logs/metrics/tracing/audit

Rules: exclude `docs/review-ledger/.archive/`; read only categories implied by the current step's REQ/RISK scope; optionally filter by `#tag`; never auto-load all ledger files by default.

## Ephemeral capture (`cr-log.md` / `learnings.md`, mid-run only)

Capture is mid-run, plan-folder-local, and **script-only** via `Add-WorkflowNote.ps1` — do not hand-edit these files and do not write `docs/review-ledger/*` during capture. `Add-WorkflowNote` resolves the log path itself (`assets/logs/<file>` in the current layout, plan-folder root for legacy plans), so pass `-PlanDir` and never a file path:

- Initialize a phase section (header + `No entries for this phase.` placeholder) by calling `Add-WorkflowNote` with no `-Message`.
- `cr-log.md` (`-Kind CrLog`): interactive `ci` persists `@cr` report + triage; autopilot persists `code-review`/`rubber-duck` findings with `-Src code-review`; standalone `cr` persists nothing.
- `learnings.md` (`-Kind Learnings`): append only on `rework>1`, `plan-contradiction`, or `reusable-pattern` triggers; the script replaces the phase placeholder and caps at 10 entries per plan with one `overflow-summary` fold.
- Stage and commit the changed log by explicit filename.

Fail-loud: missing required sections/placeholders fail; an intentionally empty `No entries for this phase.` section stays valid.
