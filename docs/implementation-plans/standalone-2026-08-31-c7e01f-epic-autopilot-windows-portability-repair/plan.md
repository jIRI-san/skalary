# c7e01f: Epic autopilot Windows portability repair
<!-- plan-id: c7e01f -->
<!-- cip-stage: drafted -->
<!-- planning-confirmed: sha256:33d51dbc7728b57ff22a3678896f03ed815fd01a30d1ac89a1f987a4becab9cd -->
<!-- depends-on: a5ad22 -->
<!-- Folder naming: <epic-id|standalone>-<yyyy-mm-dd>-<6hex>-<slug> · plan-id is the canonical handle (date/slug/hash all resolve via Resolve-Plan). New-Plan.ps1 fills these in. -->

<!-- execution-mode: container-autopilot -->
<!-- scope: plan -->
<!-- evidence: required -->
<!-- phase-budget-points: 4 -->
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

## Phase 1: Windows portability repair
<!-- worktree: (recorded by /ci when worktree is created) -->

- [x] 1.1 Repair final-crosscheck Capture handling so CRLF restoration, long Windows fixture paths, missing `StatePath`, and staged/unstaged abrupt residue are classified deterministically without weakening exact-path or clean-worktree gates (REQ-1, REQ-2, RISK-1, RISK-2) `M`
- [x] 1.2 Add cross-platform regression coverage for the three observed Windows failures, synchronize owned plugin/dogfood copies and related design notes, and preserve the append-only `a5ad22` Wrap and retained evidence unchanged (REQ-1, REQ-2, REQ-3, RISK-1, RISK-2, RISK-3) [after: 1.1] `M`
