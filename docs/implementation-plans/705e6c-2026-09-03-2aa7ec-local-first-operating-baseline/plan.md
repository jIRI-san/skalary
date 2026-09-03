# 2aa7ec: Local-first operating baseline
<!-- plan-id: 2aa7ec -->
<!-- cip-stage: dr-round-1 -->
<!-- planning-confirmed: sha256:07eba3e703437462a765a8d8b3c0233598c06193d4f89010b76c2c9c5c7816b0 -->
<!-- epic: 705e6c -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
<!-- scope: step -->
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
- Evidence receipt — `assets/evidence.md` (rebuilt by `Build-EvidenceReceipt`)
- Run logs — `assets/logs/capture.md`, `assets/logs/cr-log.md`, `assets/logs/learnings.md` (written by `Add-WorkflowNote`)
- Review results — compact `assets/reviews/<uuid>.review.md` + `<uuid>.receipt.json`; live `<uuid>/` state is gitignored

A subfolder is created only when a concern needs more than one file (`assets/decisions/`, `assets/logs/`); single-file concerns stay flat under `assets/`.

## Phase 1: Usable local-first validation
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit). -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Inventory active gates, JSON, tests, notes, and contracts with category counts, reasons, and canonical child owners (REQ-2, REQ-5, REQ-6, REQ-7, RISK-1, RISK-2, RISK-4, RISK-5) `M`
- [ ] 1.2 Resolve every uncertain test disposition before deletion (REQ-5, REQ-6, RISK-1) [after: 1.1] @human `S`
  <details><summary>Details</summary>

  **Steps:**
  1. Open `assets/ownership.md`.
  2. For each row whose disposition is `uncertain`, choose `keep` or `delete` and add a short value reason.
  3. Save the file with no remaining `uncertain` rows.

  **Verify:** every former uncertain test row has one final disposition and retained rows name current behavior, an external format, or a high-impact regression.

  **Rollback:** restore the affected rows to `uncertain`; no source or test deletion occurs in this step.

  </details>
- [ ] 1.3 Deliver confined focused runners, remove workflows/implicit broad aliases, and update directly invalidated guidance (REQ-1, REQ-2, REQ-3, REQ-4, REQ-11, RISK-2, RISK-3) [after: 1.2] `L`

## Phase 2: Value and format cleanup
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 2.1 Apply baseline test dispositions and delete tier, profile, coverage, and workflow-only support (REQ-2, REQ-4, REQ-5, REQ-6, RISK-1, RISK-2, RISK-5) [after: 1.3] `L`
- [ ] 2.2 Convert or delete baseline-owned internal JSON with its producers/consumers and bind transferred rows into child references (REQ-5, REQ-7, RISK-4, RISK-5) [after: 2.1] `M`
- [ ] 2.3 Synchronize local-first design notes, architecture indexes, and affected provisional contracts (REQ-1, REQ-2, REQ-7, REQ-11, RISK-2) [after: 2.2] `S`

## Phase 3: Ergonomic shared rules
<!-- worktree: (recorded by /ci when worktree is created) -->

- [ ] 3.1 Establish equivalent informed choices, direct-script approval guidance, and focused host fixtures (REQ-8, RISK-6) [after: 2.3] `M`
- [ ] 3.2 Retain the bounded historical adapter and remove conflicting broad-history guidance (REQ-9) [after: 3.1] `M`
- [ ] 3.3 Publish the advisory cost RFC, close every baseline ownership row, and run only focused evidence (REQ-1, REQ-5, REQ-10, REQ-11, RISK-5, RISK-6) [after: 3.2] `M`
