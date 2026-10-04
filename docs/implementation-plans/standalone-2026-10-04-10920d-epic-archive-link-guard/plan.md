# 10920d: Reject linked files during epic archival
<!-- plan-id: 10920d -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:68713b400652ac28c53dc9a600b4b50cc2923098cd4d2e9d27debd52c50cb593 -->
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

## Phase 1: Refuse linked epic sources before archival
<!-- worktree: (recorded by /ci when worktree is created) -->
<!-- Steps with no [after:] annotation can start immediately and run in parallel. -->
<!-- Roles: @ai-agent (default, not annotated) or @human (explicit).
     Nontrivial AI steps carry a compact details block with Outcome, Likely touchpoints, Constraints,
     Verify, and—when uncertain or high risk—Stop/escalate when. Omit it for self-explanatory S work. -->
<!-- Sizes: S (< 30 min) · M (30 min – 2 h) · L (2 h+) -->
<!-- Point legend: S=1, M=2, L=3 (phase-budget cap comes from the phase-budget-points marker; default 6) -->

- [ ] 1.1 Add linked-source regression fixtures (REQ-1, REQ-2, RISK-1) `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** isolated archive fixtures prove a linked `epic.md` and a linked descendant cause an
  explicit refusal without changing the external target, refreshing the child table, or moving the
  active epic; a linked source is also refused when invoked with `-WhatIf`.

  **Likely touchpoints:** `tests/skalary/ArchiveEpic.Tests.ps1` and its existing temporary-repository
  fixture.

  **Constraints:** create links only inside disposable fixtures. Do not skip a link case silently when
  the host cannot create the required link; report the host limitation and stop.

  **Verify:** `test:ArchiveEpic.LinkedEpicFile`, `test:ArchiveEpic.LinkedDescendant`, a linked-source
  `-WhatIf` assertion, and the existing `test:ArchiveEpic` cases.

  **Stop/escalate when:** the host cannot create a file symlink or directory reparse fixture needed to
  prove the corresponding refusal.

  </details>
- [ ] 1.2 Preflight epic source links before refresh and move (REQ-1, REQ-2, RISK-2) [after: 1.1] `M`
  <details><summary>Implementation contract</summary>

  **Outcome:** immediately after resolving the active epic, `Archive-Epic.ps1` refuses a linked
  `epic.md` or any linked/reparse entry in the epic folder before completion/collision gates or
  `ShouldProcess`. The refusal also applies with `-WhatIf` and occurs before invoking `New-Epic.ps1`
  to refresh the generated child table or moving the folder.

  **Likely touchpoints:** `scripts/skalary/Archive-Epic.ps1` and
  `tests/skalary/ArchiveEpic.Tests.ps1`.

  **Constraints:** inspect link/reparse attributes before descending into an entry; do not follow
  linked directories. Keep the change local to epic archival, preserve `ShouldProcess`, existing
  completion/collision gates, and normal archive behavior. Do not add a filesystem framework, lock,
  or unrelated changes to plan archival.

  **Verify:** focused `test:ArchiveEpic` cases prove both linked targets remain unchanged and the epic
  stays active on refusal; existing complete, incomplete, active-child, collision, and `WhatIf` cases
  still pass.

  **Stop/escalate when:** a supported filesystem exposes a link form the preflight cannot identify
  without following it, or a required link fixture cannot be exercised.

  </details>
