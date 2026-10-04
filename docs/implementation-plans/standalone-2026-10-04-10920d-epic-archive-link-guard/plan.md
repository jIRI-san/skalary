# 10920d: Reject linked files during epic archival
<!-- plan-id: 10920d -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:01310bfd6e684d4a6509739d9c5ce8901a9cb579e5606e11597220d35f656f70 -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- Optional execution metadata — defaults used by /ci mode selection -->
<!-- execution-mode: manual -->
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

## Phase 1: Refuse linked epic.md before archive refresh
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [x] 1.1 Add the linked epic.md regression (REQ-1, REQ-2, RISK-1) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** one isolated real file-symlink fixture proves a linked `epic.md` causes an
  explicit refusal without changing the external target, refreshing the child table, or moving the
  active epic.

  **Likely touchpoints:** `tests/skalary/ArchiveEpic.Tests.ps1` and its existing temporary-repository
  fixture.

  **Constraints:** create the link only inside a disposable fixture on a capable non-elevated host.
  No junction, descendant traversal, collision-precedence, or separate linked-source WhatIf fixtures.
  Report unsupported capability explicitly rather than counting it as a pass.

  **Verify:** `test:ArchiveEpic.LinkedEpicFile` and the existing `test:ArchiveEpic` cases.

  **Stop/escalate when:** no available non-elevated host can create the required real file symlink.
  Do not elevate the coding app or change host-wide settings.

  </details>
- [x] 1.2 Guard epic.md before confirmation and refresh (REQ-1, REQ-2, RISK-2) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** `Archive-Epic.ps1` refuses a linked/reparse `epic.md` before `ShouldProcess` and
  invoking `New-Epic.ps1` to refresh the generated child table.

  **Likely touchpoints:** `scripts/skalary/Archive-Epic.ps1` and
  `tests/skalary/ArchiveEpic.Tests.ps1`.

  **Constraints:** use a local epic.md attribute check, not recursive traversal. Preserve inventory
  reads, existing directory guards, `ShouldProcess`, completion/collision checks, and ordinary archive
  behavior. Sync canonical script copies and update directly related design notes. No filesystem
  framework, lock, unrelated plan-archive changes, or new error precedence.

  **Verify:** focused `test:ArchiveEpic` cases prove the linked target remains unchanged and the epic
  stays active on refusal; existing complete, incomplete, active-child, collision, and `WhatIf` cases
  still pass.

  **Stop/escalate when:** the real file-symlink regression cannot be exercised on an available
  non-elevated host, or the local attribute guard fails to detect that link.

  </details>
