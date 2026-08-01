# Decision: plan folder layout — `plan.md` plus `assets/`

## Target layout

```
<yyyy-mm-dd>-<6hex>-<slug>/
  plan.md                     <- the ONLY file at plan-folder root
  assets/
    intent.md                 <- goal, desired outcome, success signals, non-goals, definition of done
    requirements.md           <- REQ table
    risks.md                  <- RISK table
    decisions.md              <- one-line index into decisions/ records
    references.md             <- design notes, arch contracts, prior plans consulted
    evidence.md               <- typed-evidence receipt (single file, so no folder)
    decisions/<topic>.md      <- extended rationale records
    logs/{capture,cr-log,learnings}.md
```

Rules:

- `plan.md` keeps only: title + `plan-id` anchor, header markers, a one-line link per asset, and the phases/steps.
- A subfolder is created only when a concern needs **more than one file** (`decisions/`, `logs/`). A single-file concern stays a flat file under `assets/` — which is why the evidence receipt is `assets/evidence.md`, not `assets/evidence/evidence.md`. `Build-EvidenceReceipt` and the archival gate both resolve that path, so an ambiguous rule there would be load-bearing.
- Asset writes stay script-mediated where they already are: `Add-WorkflowNote` owns the log files, `Build-EvidenceReceipt` + `/ci` own the receipt, `New-Plan` owns scaffolding. **All of these must become layout-aware in the same phase** — otherwise writers target the legacy root while readers look under `assets/`, producing silent split-brain and an empty harvest source.
- Scaffolded asset files carry an explicit placeholder, never zero bytes, so "present-but-empty" remains distinguishable from "authored".

## Why

Three problems with the monolithic `plan.md`:

- **Size.** The validator warns at 400 lines and blocks at 700. Requirement tables and risk tables consume that budget before any steps are written, which pushes rationale out of the plan entirely instead of into a linked file.
- **Context.** `/ci` reads the whole `plan.md` on every step, so risk prose and requirement rationale are re-read hundreds of times for work that touches neither.
- **Cross-referencing.** A stable per-concern filename makes prior-plan requirements and decisions addressable (`Get-PlanIndex.ps1`, REQ-6) instead of requiring a full-plan parse.

## Backward compatibility

No migration. `Get-PlanMetadata` gains `Resolve-PlanSection`, which resolves **per section** — not per plan — and lives *inside* the metadata parser rather than at the `Test-Plan` call boundary. That placement matters: `Get-PlanMetadata` builds `.Requirements` / `.Risks` for `Test-Plan`, `Get-PlanState`, `Get-NextStep`, and the evidence loop alike. Resolving only at the `Test-Plan` boundary would leave every other consumer with empty requirements the moment a plan migrates.

Resolution rules per section:

| State | Behaviour |
|---|---|
| Asset absent | Fall back to the in-`plan.md` table |
| Asset present, non-empty, well-formed | Use the asset |
| Asset present but empty or malformed | **Fail loud** — never silently resolve to zero requirements |
| Both asset and legacy table present | Asset wins; error when the two diverge |
| `assets/` folder present but holds no recognized files | Per-section fallback, not a whole-plan mode switch |

Consequences:

- Existing active plans and everything under `archived/` keep validating byte-for-byte unchanged.
- Historical plan prose stays historical, exactly as with the plugin rename.
- The dual path is permanent, not a migration window — archived plans are evidence, not code.

Parity is proved by tests that run **every consumer** (`Test-Plan`, `Get-PlanState`) over a legacy plan and an assets-layout twin with identical content and assert identical output, plus one case per edge condition above (RISK-3).

## Self-migration

This plan is scaffolded in the legacy layout because it predates the change. Step 1.7 migrates it once steps 1.4 and 1.6 land, which dogfoods the new layout and exercises the resolver against a real plan before anything else depends on it.

Ordering is load-bearing, not cosmetic. The migration happens **while `/ci` is executing this plan**, and `/ci` picks the first incomplete step in document order — so if migration preceded the layout-aware writers, that bad order is the one that would actually run: the plan would flip to `assets/` while `Add-WorkflowNote` still resolved logs against the plan root, producing exactly the split-brain REQ-20 exists to prevent, live, inside the run that introduced it. Hence step 1.6 (writers) precedes step 1.7 (migration) both in document order and via an explicit `[after: 1.6]` edge.

The migration itself must also be a single atomic edit: write the asset files and remove the in-`plan.md` tables together, then re-validate before committing. A window where the table is gone but the asset is not yet written would be mis-parsed by the very next `Get-PlanMetadata` call that `/ci` makes to pick the following step.
